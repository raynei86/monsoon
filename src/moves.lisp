;;;; The dreaded move generation. Prepare for some blasphemous and
;;;; ugly code.

(in-package #:monsoon)

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

(defun king-in-check-p (pos color)
  "Return true if COLOR's king is in check in POS."
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
         (diag-sliders (logior opp-bishops opp-queens))
         (orth-sliders (logior opp-rooks   opp-queens))
         ;; Pawn attacks are cast from the king square toward enemy pawns.
         (pawn-cap-e (if (eq color :white) 9 -7))
         (pawn-cap-w (if (eq color :white) 7 -9)))
    (or
      ;; Pawn attacks: check whether an opponent pawn sits where our king
      ;; could capture if it were a pawn itself.
      (logtest (ash (logand king-bb +not-file-h+) pawn-cap-e) opp-pawns)
      (logtest (ash (logand king-bb +not-file-a+) pawn-cap-w) opp-pawns)
      ;; Knight attacks
      (logtest (aref +knight-attacks+ king-sq) opp-knights)
      ;; Diagonal sliders (bishop + queen)
      (logtest (bishop-attack-mask king-sq occupied) diag-sliders)
      ;; Orthogonal sliders (rook + queen)
      (logtest (rook-attack-mask king-sq occupied) orth-sliders)
      ;; King adjacency - prevent kings from moving next to each other.
      (logtest (aref +king-attacks+ king-sq) opp-king))))

(defun legal-move-p (pos move)
  "Return true if MOVE is legal in POS."
  (let ((new-pos (do-move pos move)))
    (not (king-in-check-p new-pos (pos-side-to-move pos)))))

(defun generate-legal-moves (pos)
  "Generate the legal moves for the side to move in POS."
  (iter
    (for move in (generate-moves pos))
    (for new-pos = (do-move pos move))
    (when (not (king-in-check-p new-pos (pos-side-to-move pos)))
      (collect move))))

(defun perft (pos depth)
  "Count leaf nodes by enumerating legal moves to DEPTH."
  (if (zerop depth)
      1
      (iter
        (for move in (generate-moves pos))
        (for new-pos = (do-move pos move))
        (when (not (king-in-check-p new-pos (pos-side-to-move pos)))
          (summing (perft new-pos (1- depth)))))))
