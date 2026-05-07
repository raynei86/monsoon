;;;; The dreaded move generation. Prepare for some blasphemous and
;;;; ugly code.

(in-package #:monsoon)

;; Types and declarations 
(defstruct (move (:constructor make-move (from to &optional promotion flags)))
  (from 0 :type square)
  (to 0 :type square)
  (promotion nil :type (or null piece))
  (flags 0 :type (unsigned-byte 5)))

(serapeum:defconst +move-flag-capture+   #b00001)
(serapeum:defconst +move-flag-double+    #b00010)
(serapeum:defconst +move-flag-ep+        #b00100)
(serapeum:defconst +move-flag-kingside+  #b01000)
(serapeum:defconst +move-flag-queenside+ #b10000)

(defun move-has-flag? (move flag-keyword)
  "A neat wrapper to avoid bit fiddling
   The flags are:
   - :capture
   - :double
   - :ep
   - :kingside
   - :queenside"
  (declare (type move move) (type keyword flag-keyword))
  (logtest (move-flags move)
           (ecase flag-keyword
             (:capture   +move-flag-capture+)
             (:double    +move-flag-double+)
             (:ep        +move-flag-ep+)
             (:kingside  +move-flag-kingside+)
             (:queenside +move-flag-queenside+))))

(defun emit-moves (from targets-bb &optional (flags 0))
  "Returns a list of moves from `from` to each target in `targets-bb`"
  (it:iter
    (for target in-bitboard targets-bb)
    (it:collect (make-move from target nil flags))))

;; Attack tables
(defun direction-to-offset (direction)
  (case direction
    (:n 8)   (:s -8)  (:e 1)   (:w -1)
    (:ne 9)  (:nw 7)  (:se -7) (:sw -9)

    ;; Knight specific moves defined as combinations
    (:nne 17) (:nee 10) (:see -6) (:sse -15)
    (:ssw -17) (:sww -10) (:nww 6) (:nnw 15)))

(defmacro offsets (&rest dirs)
  "Translates compass keywords to a list of integer offsets."
  `(list ,@(mapcar #'direction-to-offset dirs)))

(defmacro generate-attack-table (directions &body check-logic)
  `(it:iter
     (it:with table = (make-array 64 :element-type 'bitboard :initial-element 0))
     (it:for sq from 0 below 64)
     (setf (aref table sq)
	   (it:iter
	     (it:for offset in (offsets ,@directions))
	     (it:for to = (+ sq offset))
	     (when (and (<= 0 to 63)
			(let ((from sq) (to to)) ,@check-logic))
	       (it:sum (ash 1 to) into attacks))
	     (it:finally (return attacks))))
     (it:finally (return table))))

(serapeum:defconst +king-attacks+
  (generate-attack-table (:n :s :e :w :ne :nw :se :sw)
    (<= (abs (- (file-of from) (file-of to))) 1))) 

(serapeum:defconst +knight-attacks+
  (generate-attack-table (:nne :nee :see :sse :ssw :sww :nww :nnw)
    (let ((df (abs (- (file-of from) (file-of to))))
	  (dr (abs (- (rank-of from) (rank-of to)))))
      (or (and (= df 1) (= dr 2))
	  (and (= dr 1) (= df 2))))))


;; Rays and sliding pieces
(defmacro generate-ray-table (direction)
  "Creates an attack table for rays going in that direction, ignoring attackers"
  (let ((offset (direction-to-offset direction)))
    `(it:iter
       (it:with table = (make-array 64 :element-type 'bitboard :initial-element 0))
       (it:for sq from 0 below 64)
       (setf (aref table sq)
	     (it:iter
	       (it:for current initially sq then next)
	       (it:for next = (+ current ,offset))
	       (it:while (and (<= 0 next 63)
			      (<= (abs (- (file-of next) (file-of current))) 1)))
	       (it:sum (ash 1 next) into ray)
	       (it:finally (return ray))))
       (it:finally (return table)))))

(serapeum:defconst +rays+
  (list (cons :n (generate-ray-table :n))  (cons :ne (generate-ray-table :ne))
	(cons :e (generate-ray-table :e))  (cons :se (generate-ray-table :se))
	(cons :s (generate-ray-table :s))  (cons :sw (generate-ray-table :sw))
	(cons :w (generate-ray-table :w))  (cons :nw (generate-ray-table :nw))))

(defmacro ray (direction square)
  "Look up the precomputed ray mask for direction at a square"
  `(aref (cdr (assoc ,direction +rays+)) ,square))

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
  "Attacks along a positive ray from square, cut off at first obstacle"
  (ray-attacks square direction occupied lsb))

(defun ray-attacks- (square direction occupied)
  "Attacks along a negative ray from square, cut off at first obstacle"
  (ray-attacks square direction occupied msb))

;; Defined as macros because of the anaphoric nature you see below. I
;; need to reference a `from` square that is simply not existent in
;; `generate-slider-moves`, but is present in
;; `generate-moves-for-sliders`. Defining them as macros opens them up
;; to that necessary context.
(defmacro rook-attack-mask (square occupied)
  `(logior (ray-attacks+ ,square :n ,occupied)
          (ray-attacks+ ,square :e ,occupied)
          (ray-attacks- ,square :s ,occupied)
          (ray-attacks- ,square :w ,occupied)))

(defmacro bishop-attack-mask (square occupied)
  `(logior (ray-attacks+ ,square :ne ,occupied)
           (ray-attacks+ ,square :nw ,occupied)
           (ray-attacks- ,square :se ,occupied)
           (ray-attacks- ,square :sw ,occupied)))

(defmacro queen-attack-mask (square occupied)
  `(logior (rook-attacks ,square ,occupied)
	   (bishop-attacks ,square ,occupied)))

(defmacro generate-major-piece-moves (pieces-bb attack-expr friendly enemy)
  "Generate pseudo-legal moves for pieces that are not pawns in pieces-bb"
  `(it:iter
     (for from in-bitboard ,pieces-bb)
     (let* ((attacks (logandc2 ,attack-expr ,friendly))
	    (captures (logand attacks ,enemy))
	    (quiets (logandc2 attacks ,enemy)))
       (it:appending (emit-moves from captures +move-flag-capture+))
       (it:appending (emit-moves from quiets)))))

;; Oh my, this is amazingly concise
(defun generate-knight-moves (position)
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :knight side))
     (aref +knight-attacks+ from)
     friendly enemy)))

(defun generate-king-moves (position)
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :king side))
     (aref +king-attacks+ from)
     friendly enemy)))

(defun generate-rook-moves (position)
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :rook side))
     (rook-attacks from occupied)
     friendly enemy)))

(defun generate-bishop-moves (position)
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :bishop side))
     (bishop-attacks from occupied)
     friendly enemy)))

(defun generate-queen-moves (position)
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :bishop side))
     (queen-attacks from occupied)
     friendly enemy)))

;; Pawn move generation
;; These masks just set the bit "north"/"south" of a board with a set bit
(defun north (bb) (logand (ash bb  8) +full-board+))
(defun south (bb) (logand (ash bb -8) +full-board+))

(defmacro with-pawn-params (side &body body)
  "Bind pawn movement parameters for `side. All shifts are from the
   perspective of the board (east = toward file H), not the pawn."
  `(let ((push-fn     (if (eq ,side :white) #'north #'south))
	 (push-shift  (if (eq ,side :white)  8  -8))
	 (cap-e-shift (if (eq ,side :white)  9  -7)) ; NE / SE
	 (cap-w-shift (if (eq ,side :white)  7  -9)) ; NW / SW
	 (start-rank  (if (eq ,side :white) +rank-2+ +rank-7+))
	 (promo-rank  (if (eq ,side :white) +rank-8+ +rank-1+)))
     ,@body))

(defmacro emit-pawn-moves (targets shift &optional (flags 0))
  "Emit moves for all targets, deriving the source square as (target - shift)."
  `(it:iter
    (for target in-bitboard ,targets)
    (it:collect (make-move (- target ,shift) target nil ,flags))))

(defmacro emit-pawn-promos (targets shift &optional (flags 0))
  "Emit all 4 promotion types as moves"
  `(it:iter
     (for target in-bitboard ,targets)
     (it:for promo in '(:queen :rook :bishop :knight))
     (it:collect (make-move (- target ,shift) target promo ,flags))))

(defun generate-pawn-moves (position)
  ;; A lot to unpack here. So push1 checks if moving forward is valid
  ;; by pushing the `pawns` bitboard forward and ANDing it with the
  ;; bitboard representing empty space, essentially only allowing only
  ;; empty squares to be in front.

  ;; push2 checks if push1 landed on the rank in front of the
  ;; start-rank, then shifts only those moves forward again once more.

  ;; cap-e and cap-w mask out any pawns on h or a, as if they capture
  ;; to east or west (depending on their location), they will fly off the board.
  (with-position (side occupied friendly enemy) position
    (with-pawn-params side
      (let* ((pawns (aref (pos-boards position) (colored-piece-index :pawn side)))
             (empty (logand (lognot occupied) +full-board+))
	     (moves '())

             ;; Pushes
             (push1 (logand (funcall push-fn pawns) empty))
             (push2 (logand (funcall push-fn (logand push1 start-rank)) empty))

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

        (push (emit-pawn-moves push1-quiet push-shift) moves)
        (push (emit-pawn-moves push2 (* 2 push-shift) +move-flag-double+) moves)
        (push (emit-pawn-moves cap-e-quiet cap-e-shift +move-flag-capture+) moves)
        (push (emit-pawn-moves cap-w-quiet cap-w-shift +move-flag-capture+) moves)

        (push (emit-pawn-promos push1-promo push-shift) moves)
        (push (emit-pawn-promos cap-e-promo cap-e-shift +move-flag-capture+) moves)
        (push (emit-pawn-promos cap-w-promo cap-w-shift +move-flag-capture+) moves)

        ;; En passant — same logic as captures, but targeting the ep square alone
        (when (pos-ep-square position)
          (let* ((ep-bb    (ash 1 (pos-ep-square position)))
                 (ep-cap-e (logand (ash (logand pawns +not-file-h+) cap-e-shift) ep-bb))
                 (ep-cap-w (logand (ash (logand pawns +not-file-a+) cap-w-shift) ep-bb))
                 (ep-flags (logior +move-flag-capture+ +move-flag-ep+)))
            (push (emit-pawn-moves ep-cap-e cap-e-shift ep-flags) moves)
            (push (emit-pawn-moves ep-cap-w cap-w-shift ep-flags) moves)))
	moves))))
