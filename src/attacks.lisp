;;;; Attack tables, ray math, attacked squares, checks, and pins.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))

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
  "Translates compass keywords to a list of integer offsets.
   DIRS may arrive as a quoted literal list when spliced in by
   GENERATE-ATTACK-TABLE, so unwrap a leading QUOTE."
  (let ((dirs (if (and (consp dirs) (eq (first dirs) 'quote))
                  (second dirs)
                  dirs)))
    `(list ,@(mapcar (lambda (dir) (direction->offset dir)) dirs))))

(defmacro generate-attack-table (directions &body check-logic)
  "Build a 64-entry table of attack bitboards for DIRECTIONS.
   CHECK-LOGIC runs with FROM and TO bound to a square and one of its
   candidate neighbors; the neighbor is kept when it returns true."
  `(let ((table (make-array 64 :element-type 'bitboard :initial-element 0)))
     (dotimes (sq 64 table)
       (setf (aref table sq)
             (loop for offset in (offsets ,@directions)
                   for to = (+ sq offset)
                   when (and (<= 0 to 63)
                             (let ((from sq) (to to)) ,@check-logic))
                     sum (ash 1 to) of-type bitboard)))))

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
    `(let ((table (make-array 64 :element-type 'bitboard :initial-element 0)))
       (dotimes (sq 64 table)
         (setf (aref table sq)
               (loop for current = sq then next
                     for next = (+ current ,offset)
                     while (and (<= 0 next 63)
                                (<= (abs (- (file-of next) (file-of current))) 1))
                     sum (ash 1 next) of-type bitboard))))))

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
  "Attacks along a positive ray from square, cut off at first obstacle"
  (declare (type square square)
	   (type keyword direction)
	   (type bitboard occupied))
  (ray-attacks square direction occupied lsb))

(defun ray-attacks- (square direction occupied)
  "Attacks along a negative ray from square, cut off at first obstacle"
  (declare (type square square)
	   (type keyword direction)
	   (type bitboard occupied))
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
  `(let ((acc (the bitboard 0)))
     (do-bitboard (sq ,bb acc)
       (setf acc (logior acc (the bitboard ,expr))))))

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
         (params  (side-params color))
         (cap-e   (side-cap-e-shift params))
         (cap-w   (side-cap-w-shift params)))
    (logior
     (logior (logand (ash (logand pawns +not-file-h+) cap-e) +full-board+)
             (logand (ash (logand pawns +not-file-a+) cap-w) +full-board+))
     (union-attacks knights (aref +knight-attacks+ sq))
     (union-attacks (logior bishops queens) (bishop-attack-mask sq occupied))
     (union-attacks (logior rooks queens)   (rook-attack-mask sq occupied))
     (union-attacks king (aref +king-attacks+ sq)))))

(defun attacked-by-kingless (pos color)
  "Return a bitboard of every square COLOR's opponent attacks, computed with
   COLOR's king removed from occupancy. A king may move to any square outside
   this set, and COLOR is in check exactly when its king square is in it."
  (declare (type position pos) (type color color))
  (let ((king-bb (aref (pos-boards pos) (colored-piece-index :king color))))
    (attacked-by pos (opponent color)
                 :occupied (logandc2 (pos-occupied-squares pos) king-bb))))

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
    (dolist (dir '(:ne :nw :se :sw :n :e :s :w))
      (let* ((plus-p (or (eq dir :n) (eq dir :e) (eq dir :ne) (eq dir :nw)))
             (diagonal-p (or (eq dir :ne) (eq dir :nw) (eq dir :se) (eq dir :sw)))
             (sliders (if diagonal-p diag-sliders orth-sliders))
             (ray-bb (ray dir king-sq))
             (blockers (logand ray-bb occupied)))
        (unless (zerop blockers)
          (let* ((near (the square (if plus-p (lsb blockers) (msb blockers))))
                 (near-bit (ash 1 near))
                 (rest (logandc2 blockers near-bit)))
            (unless (zerop rest)
              (let ((far (the square (if plus-p (lsb rest) (msb rest)))))
                (when (and (logbitp near own)
                           (logbitp far sliders))
                  (setf pinned (logior pinned near-bit))
                  (unless pin-lines
                    (setf pin-lines (make-array 64 :element-type 'bitboard :initial-element 0)))
                  (setf (aref pin-lines near)
                        (logior (ray dir king-sq) (ray (opposite-dir dir) king-sq))))))))))
    (values pinned pin-lines)))

;;; Interface declarations for callers in other compilation units.
;;; Without these, returned bitboards lose their inferred type at FASL
;;; boundaries and callers fall back to generic (boxing) arithmetic.
(declaim (ftype (function (square keyword bitboard) bitboard)
                ray-attacks+ ray-attacks-))

(declaim (ftype (function (position color) bitboard)
                attacked-by-kingless checkers))

(declaim (ftype (function (position color &key (:occupied bitboard)) bitboard)
                attacked-by))

(declaim (ftype (function (position color) t) king-in-check-p))

(declaim (ftype (function (position color) (values bitboard t)) pinned-pieces))
