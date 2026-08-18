;;;; The meat, the heart, the board representation that will be used
;;;; by the library. Each position is represented using the standard
;;;; bitboard approach with all the neat info tacked inside.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))
(declaim (inline occupied-p color-at piece-at occupant-at place-piece! remove-piece! opponent))

(defstruct (position (:conc-name pos-)
		     (:copier nil))
  "A chess position. What more do you expect?"

  (boards     ; The 12 bitboards for both each different colored piece
   (make-array 12 :element-type 'bitboard :initial-element 0)
   :type (simple-array bitboard (12)))

  (by-color   ; Colored bitboard, shows squares occupied by each color
   (make-array 2 :element-type 'bitboard :initial-element 0)
   :type (simple-array bitboard (2)))

  (occupied-squares		  ; Union of the two colored bitboards
   0
   :type bitboard)

  (side-to-move :white :type color)
  (castling     0   :type castling-rights)
  (ep-square    nil   :type (or null square))
  (halfmove-clock 0   :type (unsigned-byte 7))
  (fullmove-number 1   :type fixnum)
  (hash         0   :type hash-key))  ; Zobrist hash not implemented yet, keep it for now

(defun occupied-p (position square)
  "Return true if SQUARE is occupied in POSITION."
  (declare (type square square))
  (logbitp square (pos-occupied-squares position)))

(defun color-at (position square)
  (declare (type square square))
  "Returns the color of the piece on `square`. Assumes the square is occupied."
  (if (logbitp square (aref (pos-by-color position) 0))
      :white
      (if (logbitp square (aref (pos-by-color position) 1))
	  :black
	  nil)))

(defun piece-at (position square)
  (declare (type square square))
  "Returns the piece type on `square`. Assumes the square is occupied."
  (let* ((color (color-at position square))
         (boards (pos-boards position)))
    (cond
      ((logbitp square (aref boards (colored-piece-index :pawn   color))) :pawn)
      ((logbitp square (aref boards (colored-piece-index :knight color))) :knight)
      ((logbitp square (aref boards (colored-piece-index :bishop color))) :bishop)
      ((logbitp square (aref boards (colored-piece-index :rook   color))) :rook)
      ((logbitp square (aref boards (colored-piece-index :queen  color))) :queen)
      ((logbitp square (aref boards (colored-piece-index :king   color))) :king))))

(defun occupant-at (position square)
  "Return the piece and color at SQUARE, or NIL values if empty."
  (if (occupied-p position square)
      (values (piece-at  position square)
              (color-at position square))
      (values nil nil)))

(defmacro with-square ((piece color) position square &body body)
  "Bind `piece` and `color` for the occupant of `square` in `position`.
   Both are NIL if the square is empty."
  `(multiple-value-bind (,piece ,color)
       (occupant-at ,position ,square)
     ,@body))

(defun opponent (color)
  "Return the opposing color."
  (declare (type color color))
  (if (eq color :white) :black :white))

(defun place-piece! (position square colored-piece-code)
  "Adds a piece to the board and updates all tracking bitboards."
  (declare (type position position) (type square square))
  (let ((mask  (ash 1 square))
        (color (logand colored-piece-code 1)))
    (setf (aref (pos-boards position) colored-piece-code) (logior (aref (pos-boards position) colored-piece-code) mask)
          (aref (pos-by-color position) color)            (logior (aref (pos-by-color position) color) mask)
          ;; Update the occupancy bitboard (combined White + Black)
          (pos-occupied-squares position)                        (logior (pos-occupied-squares position) mask)))
  position)

(defun remove-piece! (position square colored-piece-code)
  "Clears a piece from the board and updates all tracking bitboards."
  (declare (type position position) (type square square))
  (let ((mask  (ash 1 square))
        (color (logand colored-piece-code 1)))
    (setf (aref (pos-boards position) colored-piece-code) (logandc2 (aref (pos-boards position) colored-piece-code) mask)
          (aref (pos-by-color position) color)            (logandc2 (aref (pos-by-color position) color) mask)
          ;; Update the occupancy bitboard (combined White + Black)
          (pos-occupied-squares position)                        (logandc2 (pos-occupied-squares position) mask)))
  position)

(defmacro with-position ((side occupied friendly enemy) position &body body)
  "Binds some necessary information about the position"
  (with-gensyms (pos color-idx)
    `(let* ((,pos        ,position)
            (,side     (pos-side-to-move ,pos))
            (,color-idx      (color-index ,side))
            (,occupied (pos-occupied-squares ,pos))
            (,friendly (aref (pos-by-color ,pos) ,color-idx))
            (,enemy    (aref (pos-by-color ,pos) (- 1 ,color-idx))))
       (declare (ignorable ,occupied)
		(ignorable ,friendly)
		(ignorable ,enemy)
		(ignorable ,color-idx))
       ,@body)))

(defun copy-position (pos)
  "Return a copy of POS with duplicated arrays."
  (make-position
    :boards           (copy-seq (pos-boards pos))
    :by-color         (copy-seq (pos-by-color pos))
    :occupied-squares (pos-occupied-squares pos)
    :side-to-move     (pos-side-to-move pos)
    :castling         (pos-castling pos)
    :ep-square        (pos-ep-square pos)
    :halfmove-clock   (pos-halfmove-clock pos)
    :fullmove-number  (pos-fullmove-number pos)
    :hash             (pos-hash pos)))
