;;;; The dreaded move generation. Prepare for some blasphemous and
;;;; ugly code.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))

;; Types and declarations 
(defstruct (move (:constructor make-move (from to &optional promotion flags)))
  "A move between two squares, with an optional promotion piece and flag bits."
  (from 0 :type square)
  (to 0 :type square)
  (promotion nil :type (or null piece))
  (flags 0 :type (unsigned-byte 5)))

(defmacro with-move ((from to promotion flags) move &body body)
  "Destructure MOVE into FROM, TO, PROMOTION, and FLAGS bindings."
  `(let ((,from      (move-from      ,move))
         (,to        (move-to        ,move))
         (,promotion (move-promotion ,move))
         (,flags     (move-flags     ,move)))
     (declare (ignorable ,flags))
     ,@body))

(defconst +move-flag-capture+   #b00001)
(defconst +move-flag-double+    #b00010)
(defconst +move-flag-ep+        #b00100)
(defconst +move-flag-kingside+  #b01000)
(defconst +move-flag-queenside+ #b10000)

(defun emit-moves (from targets-bb &optional (flags 0))
  "Return moves from FROM to each target in TARGETS-BB."
  (declare (type square from)
           (type bitboard targets-bb))
  (iter
    (for target in-bitboard targets-bb)
    (collect (make-move from target nil flags))))

;; Attack tables
;; Precompute king and knight attacks for every square.
(defmacro direction->offset (direction)
  "Map a compass keyword (:n, :ne, ..., :nnw) to a rank/file offset."
  `(case ,direction
    (:n 8)   (:s -8)  (:e 1)   (:w -1)
    (:ne 9)  (:nw 7)  (:se -7) (:sw -9)

    ;; Knight specific moves defined as combinations
    (:nne 17) (:nee 10) (:see -6) (:sse -15)
    (:ssw -17) (:sww -10) (:nww 6) (:nnw 15)))

(defmacro offsets (&rest dirs)
  "Translates compass keywords to a list of integer offsets."
  `(iter
     (for dir in ,dirs)
     (collect (direction->offset dir))))

(defmacro generate-attack-table (directions &body check-logic)
  "Build a 64-entry table of attack bitboards for DIRECTIONS.
   CHECK-LOGIC runs with FROM and TO bound to a square and one of its
   candidate neighbors; the neighbor is kept when it returns true."
  `(iter
     (with table = (make-array 64 :element-type 'bitboard :initial-element 0))
     (for sq from 0 below 64)
     (setf (aref table sq)
	   (iter
	     (for offset in (offsets ,@directions))
	     (for to = (+ sq offset))
	     (when (and (<= 0 to 63)
			(let ((from sq) (to to)) ,@check-logic))
	       (sum (ash 1 to) into attacks))
	     (finally (return attacks))))
     (finally (return table))))

(defconst +king-attacks+
  (generate-attack-table '(:n :s :e :w :ne :nw :se :sw)
    (<= (abs (- (file-of from) (file-of to))) 1))) 

(defconst +knight-attacks+
  (generate-attack-table '(:nne :nee :see :sse :ssw :sww :nww :nnw)
    (let ((df (abs (- (file-of from) (file-of to))))
	  (dr (abs (- (rank-of from) (rank-of to)))))
      (or (and (= df 1) (= dr 2))
	  (and (= dr 1) (= df 2))))))


;; Rays and sliding pieces
(defmacro generate-ray-table (direction)
  "Creates an attack table for rays going in that direction, ignoring attackers"
  (let ((offset (direction->offset direction)))
    `(iter
       (with table = (make-array 64 :element-type 'bitboard :initial-element 0))
       (for sq from 0 below 64)
       (setf (aref table sq)
	     (iter
	       (for current initially sq then next)
	       (for next = (+ current ,offset))
	       (while (and (<= 0 next 63)
			      (<= (abs (- (file-of next) (file-of current))) 1)))
	       (sum (ash 1 next) into ray)
	       (finally (return ray))))
       (finally (return table)))))

(deftype ray-table () '(simple-array bitboard (64)))
(deftype ray-set   () '(simple-array ray-table (8)))

(defconst +rays+
  (the ray-set
       (make-array 8 :element-type 'ray-table
		     :initial-contents
		   (list (generate-ray-table :n) (generate-ray-table :ne)
			 (generate-ray-table :e) (generate-ray-table :se)
			 (generate-ray-table :s) (generate-ray-table :sw)
			 (generate-ray-table :w) (generate-ray-table :nw)))))

(defmacro ray (direction square)
  "Look up the precomputed ray mask for direction at a square"
  `(let ((dir-index (ecase ,direction
		      (:n 0) (:ne 1) (:e 2) (:se 3)
		      (:s 4) (:sw 5) (:w 6) (:nw 7))))
   (the bitboard
	 (aref (the ray-table (aref (the ray-set +rays+) dir-index)) ,square))))

(defmacro ray-attacks (square direction occupied blocker-func)
  "Takes a square, direction of the ray, and a bitboard of occupied squares.
   Then returns a ray that factors in obstacles."
  `(let* ((ray (ray ,direction ,square))
	  (blockers (logand ray ,occupied))) ; All occupied squares on ray path
     (if (zerop blockers)
	 ray
	 ;; When there is a blocker, cut off the ray by xoring it with
	 ;; another ray at the obstacle
	 (logxor ray (ray ,direction (,blocker-func blockers))))))

(defun ray-attacks+ (square direction occupied)
  (declare (type square square)
	   (type keyword direction)
	   (type bitboard occupied))
  "Attacks along a positive ray from square, cut off at first obstacle"
  (ray-attacks square direction occupied lsb))

(defun ray-attacks- (square direction occupied)
  (declare (type square square)
	   (type keyword direction)
	   (type bitboard occupied))
  "Attacks along a negative ray from square, cut off at first obstacle"
  (ray-attacks square direction occupied msb))

;; Slider attack macros are anaphoric; FROM is bound by generate-major-piece-moves.
(defmacro rook-attack-mask (square occupied)
  "Rook attacks from SQUARE given OCCUPIED squares."
  `(logior (ray-attacks+ ,square :n ,occupied)
          (ray-attacks+ ,square :e ,occupied)
          (ray-attacks- ,square :s ,occupied)
          (ray-attacks- ,square :w ,occupied)))

(defmacro bishop-attack-mask (square occupied)
  "Bishop attacks from SQUARE given OCCUPIED squares."
  `(logior (ray-attacks+ ,square :ne ,occupied)
           (ray-attacks+ ,square :nw ,occupied)
           (ray-attacks- ,square :se ,occupied)
           (ray-attacks- ,square :sw ,occupied)))

(defmacro queen-attack-mask (square occupied)
  "Queen attacks from SQUARE given OCCUPIED squares."
  `(logior (rook-attack-mask ,square ,occupied)
	   (bishop-attack-mask ,square ,occupied)))

(defmacro union-attacks (bb expr)
  "OR together EXPR evaluated for each set bit of BB. SQ is bound to each bit index."
  `(iter
     (with acc = 0)
     (for sq in-bitboard ,bb)
     (setf acc (logior acc ,expr))
     (finally (return acc))))

(defun attacked-by (pos color &key (occupied (pos-occupied-squares pos)))
  "Return a bitboard of every square attacked by COLOR's pieces in POS.
   OCCUPIED selects the occupancy used for slider rays; pass a copy with
   the relevant king removed to test king-move safety."
  (declare (type position pos)
           (type color color)
           (type bitboard occupied))
  (let* ((boards (pos-boards pos))
         (pawns   (aref boards (colored-piece-index :pawn   color)))
         (knights (aref boards (colored-piece-index :knight color)))
         (bishops (aref boards (colored-piece-index :bishop color)))
         (rooks   (aref boards (colored-piece-index :rook   color)))
         (queens  (aref boards (colored-piece-index :queen  color)))
         (king    (aref boards (colored-piece-index :king   color)))
         (cap-e   (if (eq color :white) 9 -7))
         (cap-w   (if (eq color :white) 7 -9)))
    (logior
     (logior (ash (logand pawns +not-file-h+) cap-e)
             (ash (logand pawns +not-file-a+) cap-w))
     (union-attacks knights (aref +knight-attacks+ sq))
     (union-attacks (logior bishops queens) (bishop-attack-mask sq occupied))
     (union-attacks (logior rooks queens)   (rook-attack-mask sq occupied))
     (union-attacks king (aref +king-attacks+ sq)))))

(defconst +between+
  ;; between[a][b] = squares strictly between a and b when they are aligned
  ;; on a file, rank, or diagonal; 0 otherwise. Used to find block squares.
  (let ((table (make-array '(64 64) :element-type 'bitboard :initial-element 0)))
    (dolist (dir '(:n :ne :e :se :s :sw :w :nw))
      (dotimes (from 64)
        (let ((offset (direction->offset dir))
              (current from)
              (between 0))
          (loop
            (let ((next (+ current offset)))
              (unless (and (<= 0 next 63)
                           (<= (abs (- (file-of next) (file-of current))) 1))
                (return))
              (setf (aref table from next) between)
              (setf between (logior between (ash 1 next)))
              (setf current next))))))
    table))

(defmacro opposite-dir (direction)
  "Return the compass direction opposite DIRECTION."
  `(ecase ,direction
     (:n :s) (:s :n) (:e :w) (:w :e)
     (:ne :sw) (:sw :ne) (:nw :se) (:se :nw)))

(defun pinned-pieces (pos side)
  "Return (values PINNED PIN-LINES). PINNED is a bitboard of SIDE's pieces
   pinned to their king by an enemy slider. PIN-LINES is a 64-entry array
   mapping each pinned piece to the line it is restricted to (NIL when no
   piece is pinned)."
  (declare (type position pos) (type color side))
  (let* ((king-sq (lsb (aref (pos-boards pos) (colored-piece-index :king side))))
         (opp (opponent side))
         (occupied (pos-occupied-squares pos))
         (own (aref (pos-by-color pos) (color-index side)))
         (opp-bishops (aref (pos-boards pos) (colored-piece-index :bishop opp)))
         (opp-rooks   (aref (pos-boards pos) (colored-piece-index :rook   opp)))
         (opp-queens  (aref (pos-boards pos) (colored-piece-index :queen  opp)))
         (diag-sliders (logior opp-bishops opp-queens))
         (orth-sliders (logior opp-rooks   opp-queens))
         (pinned 0)
         (pin-lines nil))
    (iter
      (for dir in '(:ne :nw :se :sw :n :e :s :w))
      (for diagonal-p = (or (eq dir :ne) (eq dir :nw) (eq dir :se) (eq dir :sw)))
      (for sliders = (if diagonal-p diag-sliders orth-sliders))
      (for nearest-fn = (if (or (eq dir :n) (eq dir :e) (eq dir :ne) (eq dir :nw))
                            #'lsb #'msb))
      (for ray-bb = (ray dir king-sq))
      (for blockers = (logand ray-bb occupied))
      (for near = (unless (zerop blockers) (funcall nearest-fn blockers)))
      (for near-bit = (when near (ash 1 near)))
      (for far = (and near
                      (let ((rest (logandc2 blockers near-bit)))
                        (unless (zerop rest) (funcall nearest-fn rest)))))
      (when (and near far
                 (logbitp near own)
                 (logbitp far sliders))
        (setf pinned (logior pinned near-bit))
        (unless pin-lines
          (setf pin-lines (make-array 64 :element-type 'bitboard :initial-element 0)))
        (setf (aref pin-lines near)
              (logior (ray dir king-sq) (ray (opposite-dir dir) king-sq)))))
    (values pinned pin-lines)))

(defmacro generate-major-piece-moves (pieces-bb attack-expr friendly enemy)
  "Generate pseudo-legal moves for pieces that are not pawns in pieces-bb"
  `(iter
     (for from in-bitboard ,pieces-bb)
     (let* ((attacks (logandc2 ,attack-expr ,friendly))
	    (captures (logand attacks ,enemy))
	    (quiets (logandc2 attacks ,enemy)))
       (nconcing (emit-moves from captures +move-flag-capture+))
       (nconcing (emit-moves from quiets)))))

(defun generate-knight-moves (position)
  "Generate pseudo-legal knight moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :knight side))
     (aref +knight-attacks+ from)
     friendly enemy)))

(defun generate-king-moves (position)
  "Generate pseudo-legal king moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :king side))
     (aref +king-attacks+ from)
     friendly enemy)))

(defun generate-rook-moves (position)
  "Generate pseudo-legal rook moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :rook side))
     (rook-attack-mask from occupied)
     friendly enemy)))

(defun generate-bishop-moves (position)
  "Generate pseudo-legal bishop moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :bishop side))
     (bishop-attack-mask from occupied)
     friendly enemy)))

(defun generate-queen-moves (position)
  "Generate pseudo-legal queen moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :queen side))
     (queen-attack-mask from occupied)
     friendly enemy)))

;; Pawn move generation
;; These masks just set the bit "north"/"south" of a board with a set bit
(defun shift-north (bb)
  "Shift BB one rank toward rank 8, discarding bits off the board."
  (logand (ash bb  8) +full-board+))

(defun shift-south (bb)
  "Shift BB one rank toward rank 1, discarding bits off the board."
  (logand (ash bb -8) +full-board+))

(defmacro with-pawn-params (side &body body)
  "Bind pawn movement parameters for `side. All shifts are from the
   perspective of the board (east = toward file H), not the pawn."
  `(let ((push-fn     (if (eq ,side :white) #'shift-north #'shift-south))
	 (push-shift  (if (eq ,side :white)  8  -8))
	 (cap-e-shift (if (eq ,side :white)  9  -7)) ; NE / SE
	 (cap-w-shift (if (eq ,side :white)  7  -9)) ; NW / SW
	 (start-rank  (if (eq ,side :white) +rank-2+ +rank-7+))
	 (promo-rank  (if (eq ,side :white) +rank-8+ +rank-1+)))
     ,@body))

(defmacro emit-pawn-moves (targets shift &optional (flags 0))
  "Emit moves for all targets, deriving the source square as (target - shift)."
  `(iter
    (for target in-bitboard ,targets)
    (collect (make-move (- target ,shift) target nil ,flags))))

(defmacro emit-pawn-promos (targets shift &optional (flags 0))
  "Emit all 4 promotion types as moves"
  `(iter
     (for target in-bitboard ,targets)
     (nconcing
      (iter
	(for promo in '(:queen :rook :bishop :knight))
	(collect (make-move (- target ,shift) target promo ,flags))))))

(defun generate-pawn-moves (position)
  "Generate pseudo-legal pawn moves for the side to move."
  ;; Pawn moves use shifted masks for pushes and captures.
  ;; push1/push2 are quiet advances; cap-e/cap-w are capture masks.
  (with-position (side occupied friendly enemy) position
    (with-pawn-params side
      (let* ((pawns (aref (pos-boards position) (colored-piece-index :pawn side)))
             (empty (logand (lognot occupied) +full-board+))

             ;; Pushes
             (push1 (logand (funcall push-fn pawns) empty))
	     (push2 (logand (funcall push-fn
				     (logand (funcall push-fn (logand pawns start-rank))
					     empty))
			    empty))

             ;; Captures
             (cap-e (logand (ash (logand pawns +not-file-h+) cap-e-shift) enemy))
             (cap-w (logand (ash (logand pawns +not-file-a+) cap-w-shift) enemy))

             ;; Split promotions from regular moves
             (push1-promo (logand    push1 promo-rank))
             (push1-quiet (logandc2  push1 promo-rank))
             (cap-e-promo (logand    cap-e promo-rank))
             (cap-e-quiet (logandc2  cap-e promo-rank))
             (cap-w-promo (logand    cap-w promo-rank))
             (cap-w-quiet (logandc2  cap-w promo-rank)))

        (nconc
	 (emit-pawn-moves push1-quiet push-shift) 
         (emit-pawn-moves push2 (* 2 push-shift) +move-flag-double+)
         (emit-pawn-moves cap-e-quiet cap-e-shift +move-flag-capture+)
         (emit-pawn-moves cap-w-quiet cap-w-shift +move-flag-capture+)

         (emit-pawn-promos push1-promo push-shift)
         (emit-pawn-promos cap-e-promo cap-e-shift +move-flag-capture+)
         (emit-pawn-promos cap-w-promo cap-w-shift +move-flag-capture+)

         ;; En passant uses capture logic against the ep square.
         (when (pos-ep-square position)
           (let* ((ep-bb    (ash 1 (pos-ep-square position)))
                  (ep-cap-e (logand (ash (logand pawns +not-file-h+) cap-e-shift) ep-bb))
                  (ep-cap-w (logand (ash (logand pawns +not-file-a+) cap-w-shift) ep-bb))
                  (ep-flags (logior +move-flag-capture+ +move-flag-ep+)))
	     (nconc
	      (emit-pawn-moves ep-cap-e cap-e-shift ep-flags)
	      (emit-pawn-moves ep-cap-w cap-w-shift ep-flags)))))))))


;; Castling move generation
(defconst +white-kingside-path+  (logior (ash 1 (sq :f1)) (ash 1 (sq :g1))))
(defconst +white-queenside-path+ (logior (ash 1 (sq :b1)) (ash 1 (sq :c1)) (ash 1 (sq :d1))))
(defconst +black-kingside-path+  (logior (ash 1 (sq :f8)) (ash 1 (sq :g8))))
(defconst +black-queenside-path+ (logior (ash 1 (sq :b8)) (ash 1 (sq :c8)) (ash 1 (sq :d8))))

(defconst +white-king-sq+       (sq :e1))
(defconst +black-king-sq+       (sq :e8))
(defconst +white-kingside-sq+   (sq :g1))
(defconst +black-kingside-sq+   (sq :g8))
(defconst +white-queenside-sq+  (sq :c1))
(defconst +black-queenside-sq+  (sq :c8))

;; Castling: the squares the king must not be in check on (transit + destination).
(defconst +white-kingside-king-path+  (logior (ash 1 (sq :f1)) (ash 1 (sq :g1))))
(defconst +white-queenside-king-path+ (logior (ash 1 (sq :d1)) (ash 1 (sq :c1))))
(defconst +black-kingside-king-path+  (logior (ash 1 (sq :f8)) (ash 1 (sq :g8))))
(defconst +black-queenside-king-path+ (logior (ash 1 (sq :d8)) (ash 1 (sq :c8))))

(defun castling-king-path (side flags)
  "Return the squares the king must not be in check on for a castling move."
  (let ((kingside-p (logtest flags +move-flag-kingside+)))
    (if (eq side :white)
        (if kingside-p +white-kingside-king-path+ +white-queenside-king-path+)
        (if kingside-p +black-kingside-king-path+ +black-queenside-king-path+))))

(defmacro with-castling-params (side &body body)
  "Bind castling rights, path masks, and king/rook destination squares for SIDE."
  `(let ((kingside-right  (if (eq ,side :white) +white-kingside+  +black-kingside+))
         (queenside-right (if (eq ,side :white) +white-queenside+ +black-queenside+))
         (kingside-path   (if (eq ,side :white) +white-kingside-path+  +black-kingside-path+))
         (queenside-path  (if (eq ,side :white) +white-queenside-path+ +black-queenside-path+))
         (king-sq         (if (eq ,side :white) +white-king-sq+ +black-king-sq+))
         (kingside-sq     (if (eq ,side :white) +white-kingside-sq+ +black-kingside-sq+))
         (queenside-sq    (if (eq ,side :white) +white-queenside-sq+ +black-queenside-sq+)))
     ,@body))

(defun generate-castling-moves (position)
  "Generate pseudo-legal castling moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (with-castling-params side
      (let ((rights (pos-castling position))
	    (moves '()))
	(when (and (logtest rights kingside-right)
		   (not (logtest occupied kingside-path)))
	  (push (make-move king-sq kingside-sq nil +move-flag-kingside+) moves))
	(when (and (logtest rights queenside-right)
		   (not (logtest occupied queenside-path)))
	  (push (make-move king-sq queenside-sq nil +move-flag-queenside+) moves))
	moves))))

;; Final stages, move legality and actually making the moves
(defun do-move (position move)
  "Apply MOVE to POSITION and return the resulting position."
  (let* ((new-pos (copy-position position))
         (side    (pos-side-to-move new-pos))
         (opp     (opponent side))
	 (pawn-dir (if (eq side :white) -8 +8)))
    (nest
     (with-move (from to promotion flags) move

       ;; First handle captures
       (when (logtest flags +move-flag-capture+)
	 (if (logtest flags +move-flag-ep+)
	     ;; En-passant slightly different
	     (remove-piece! new-pos
			    (+ to pawn-dir)
			    (colored-piece-index :pawn opp))
	     (remove-piece! new-pos
			    to
			    (colored-piece-index (piece-at new-pos to) opp))))

       ;; Now actually move the piece and update all the boards
       (let ((cpc (colored-piece-index (piece-at new-pos from) side)))
	 (remove-piece! new-pos from cpc)
	 (place-piece! new-pos to cpc)
	 ;; If promotion just replace over it
	 (when promotion
	   (remove-piece! new-pos to cpc)
	   (place-piece! new-pos to (colored-piece-index promotion side))))

       ;; Castling and relocate rook
       (let ((rook-cpc (colored-piece-index :rook side)))
	 (cond
	   ((logtest flags +move-flag-kingside+)
	    (remove-piece! new-pos (if (eq side :white) (sq :h1) (sq :h8)) rook-cpc)
            (place-piece!  new-pos (if (eq side :white) (sq :f1) (sq :f8)) rook-cpc))
	   ((logtest flags +move-flag-queenside+)
	    (remove-piece! new-pos (if (eq side :white) (sq :a1) (sq :a8)) rook-cpc)
            (place-piece!  new-pos (if (eq side :white) (sq :d1) (sq :d8)) rook-cpc))))

      
       ;; Set the new en passant square: only on a double pawn push, one
       ;; rank behind the destination.
       (setf (pos-ep-square new-pos)
	     (when (logtest flags +move-flag-double+)
	       (+ to pawn-dir)))

       ;; Update castling rights. Both `from` and `to` are checked so
       ;; capturing a rook on its home square strips that right
       ;; automatically.
       (setf (pos-castling new-pos)
             (logand (pos-castling new-pos)
                     (logand (aref +castling-rights-mask+ from)
                             (aref +castling-rights-mask+ to))))

       ;; Halfmove clock: reset on pawn move or capture, otherwise
       ;; increment.
       (setf (pos-halfmove-clock new-pos)
             (if (or (eq (piece-at position from) :pawn)
                     (logtest flags +move-flag-capture+))
                 0
                 (1+ (pos-halfmove-clock new-pos))))

       ;; Fullmove number increments after black's reply.
       (when (eq side :black)
         (incf (pos-fullmove-number new-pos)))

       ;; Flip the side to move.
       (setf (pos-side-to-move new-pos) opp)))
    new-pos))

(defun generate-moves (position)
  "Generate all pseudo-legal moves for the side to move."
  (nconc (generate-pawn-moves   position)
          (generate-knight-moves position)
          (generate-bishop-moves position)
          (generate-rook-moves   position)
          (generate-queen-moves  position)
          (generate-king-moves   position)
          (generate-castling-moves position)))

(defun checkers (pos color)
  "Return a bitboard of the squares of enemy pieces giving check to COLOR's king."
  (declare (type position pos) (type color color))
  (let* ((king-bb  (aref (pos-boards pos) (colored-piece-index :king color)))
         (king-sq  (lsb king-bb))
         (opp      (opponent color))
         (occupied (pos-occupied-squares pos))
         (opp-pawns   (aref (pos-boards pos) (colored-piece-index :pawn   opp)))
         (opp-knights (aref (pos-boards pos) (colored-piece-index :knight opp)))
         (opp-bishops (aref (pos-boards pos) (colored-piece-index :bishop opp)))
         (opp-rooks   (aref (pos-boards pos) (colored-piece-index :rook   opp)))
         (opp-queens  (aref (pos-boards pos) (colored-piece-index :queen  opp)))
         (opp-king    (aref (pos-boards pos) (colored-piece-index :king   opp)))
         (pawn-cap-e (if (eq color :white) 9 -7))
         (pawn-cap-w (if (eq color :white) 7 -9)))
    (logior
     (logand (ash (logand king-bb +not-file-h+) pawn-cap-e) opp-pawns)
     (logand (ash (logand king-bb +not-file-a+) pawn-cap-w) opp-pawns)
     (logand (aref +knight-attacks+ king-sq) opp-knights)
     (logand (bishop-attack-mask king-sq occupied)
             (logior opp-bishops opp-queens))
     (logand (rook-attack-mask king-sq occupied)
             (logior opp-rooks opp-queens))
     (logand (aref +king-attacks+ king-sq) opp-king))))

(defun king-in-check-p (pos color)
  "Return true if COLOR's king is in check in POS."
  (not (zerop (checkers pos color))))

(defstruct (legality-context (:constructor %make-legality-context)
                             (:conc-name legality-context-))
  "Precomputed invariants used to classify move legality without making the
   move or scanning for checks on every candidate."
  (side nil :type color)
  (king-sq 0 :type square)
  (in-check-p nil)
  (king-danger 0 :type bitboard)
  (pinned 0 :type bitboard)
  (pin-lines nil :type (or null (simple-array bitboard (64))))
  (evasion-mask 0 :type bitboard))

(defun evasion-mask (pos side)
  "Return the target squares a non-king move must reach to resolve a check on
   SIDE. Returns +FULL-BOARD+ when SIDE is not in check and 0 for double check."
  (let* ((checkers-bb (checkers pos side))
         (n (logcount checkers-bb)))
    (cond
      ((zerop n) +full-board+)
      ((> n 1) 0)
      (t (let* ((king-sq    (lsb (aref (pos-boards pos) (colored-piece-index :king side))))
                (checker-sq (lsb checkers-bb)))
           (logior (ash 1 checker-sq)
                   (aref +between+ king-sq checker-sq)))))))

(defun evasion-move-p (ctx move)
  "Return true if MOVE resolves the check recorded in context CTX.
   Only called for non-king moves while the side to move is in check."
  (with-move (from to promotion flags) move
    (declare (ignore promotion flags))
    (and (logtest (ash 1 to) (legality-context-evasion-mask ctx))
         (or (not (logbitp from (legality-context-pinned ctx)))
             (logtest (ash 1 to) (aref (legality-context-pin-lines ctx) from))))))

(defun make-legality-context (pos)
  "Build the legality invariants for POS's side to move."
  (let* ((side (pos-side-to-move pos))
         (opp (opponent side))
         (king-bb (aref (pos-boards pos) (colored-piece-index :king side)))
         (king-sq (lsb king-bb))
         (occupied (pos-occupied-squares pos))
         (king-danger (attacked-by pos opp
                                   :occupied (logandc2 occupied king-bb)))
         (in-check-p (logbitp king-sq king-danger)))
    (multiple-value-bind (pinned pin-lines)
        (pinned-pieces pos side)
      (%make-legality-context
       :side side
       :king-sq king-sq
       :in-check-p in-check-p
       :king-danger king-danger
       :pinned pinned
       :pin-lines pin-lines
       :evasion-mask (if in-check-p (evasion-mask pos side) +full-board+)))))

(defun move-legal-p (ctx pos move)
  "Return true if MOVE is legal in POS, using the precomputed context CTX."
  (let ((side (legality-context-side ctx))
        (king-sq (legality-context-king-sq ctx)))
    (with-move (from to promotion flags) move
      (declare (ignore promotion))
      (cond
        ;; Castling: illegal out of, through, or into check.
        ((logtest flags (logior +move-flag-kingside+ +move-flag-queenside+))
         (and (not (legality-context-in-check-p ctx))
              (not (logtest (attacked-by pos (opponent side))
                            (castling-king-path side flags)))))
        ;; King moves: destination must not be attacked. Enemy attacks were
        ;; computed with our king removed, so retreats onto a vacated line
        ;; (which the moving king would otherwise block) are caught.
        ((= from king-sq)
         (not (logbitp to (legality-context-king-danger ctx))))
        ;; En passant removes two pawns, which can expose a rank attack.
        ((logtest flags +move-flag-ep+)
         (not (king-in-check-p (do-move pos move) side)))
        ;; In check: only capturing the checker or blocking its line helps.
        ((legality-context-in-check-p ctx)
         (evasion-move-p ctx move))
        ;; Pinned pieces must stay on their pin line.
        ((logbitp from (legality-context-pinned ctx))
         (logtest (ash 1 to) (aref (legality-context-pin-lines ctx) from)))
        ;; Everything else is legal.
        (t t)))))

(defun legal-move-p (pos move)
  "Return true if MOVE is legal in POS."
  (move-legal-p (make-legality-context pos) pos move))

(defun generate-legal-moves (pos)
  "Generate the legal moves for the side to move in POS."
  (let ((ctx (make-legality-context pos)))
    (iter
      (for move in (generate-moves pos))
      (when (move-legal-p ctx pos move)
        (collect move)))))

(defun perft (pos depth)
  "Count leaf nodes by enumerating legal moves to DEPTH."
  (declare (type (and fixnum (integer 0 *)) depth)
           (values fixnum))
  (if (zerop depth)
      1
      (let ((ctx (make-legality-context pos)))
        (iter
          (with total = 0)
          (for move in (generate-moves pos))
          (when (move-legal-p ctx pos move)
            (setf total (the fixnum (+ total (the fixnum (perft (do-move pos move)
                                                                (1- depth)))))))
          (finally (return total))))))
