;;;; The meat, the heart, the board representation that will be used
;;;; by the library. Each position is represented using the standard
;;;; bitboard approach with all the neat info tacked inside.

(in-package #:monsoon)

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

  (by-piece	; Same idea as the color boards but for pieces instead
   (make-array 6 :element-type 'bitboard :initial-element 0)
   :type (simple-array bitboard (6)))
  
  (occupied-squares		  ; Union of the two colored bitboards
   0
   :type bitboard)

  (side-to-move :white :type color)
  (castling     0   :type castling-rights)
  (ep-square    nil   :type (or null square))
  (halfmove-clock 0   :type (integer 0 100))
  (fullmove-number 1   :type (integer 1 *))
  (hash         0   :type hash-key))  ; Zobrist hash not implemented yet, keep it for now

(defun occupied-p (position square)
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
  (let ((bit (ash 1 square)))
    (it:iter
      (it:for piece-index from 0 below 6)
      (it:finding (ecase piece-index
                    (0 :pawn) (1 :knight) (2 :bishop)
                    (3 :rook) (4 :queen)  (5 :king))
                  such-that (logtest bit (aref (pos-by-piece position) piece-index))))))

(defun occupant-at (position square)
  "Returns the colored piece at that square as an `color-pieced-code`"
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
  (declare (type color color))
  (if (eq color :white) :black :white))

(defun place-piece! (position square colored-piece-code)
  "Adds a piece to the board and updates all tracking bitboards."
  (declare (type position position) (type square square))
  (with-colored-piece-index (piece color) colored-piece-code
    (let ((mask (ash 1 square)))
      (setf (aref (pos-boards position) colored-piece-code) (logior (aref (pos-boards position) colored-piece-code) mask)
            (aref (pos-by-color position) color)           (logior (aref (pos-by-color position) color) mask)
            (aref (pos-by-piece position) piece)           (logior (aref (pos-by-piece position) piece) mask)
            ;; Update the occupancy bitboard (combined White + Black)
            (pos-occupied-squares position)                        (logior (pos-occupied-squares position) mask))))
  position)

(defun remove-piece! (position square colored-piece-code)
  "Clears a piece from the board and updates all tracking bitboards."
  (declare (type position position) (type square square))
  (with-colored-piece-index (piece color) colored-piece-code
    (let ((mask (ash 1 square)))
      (setf (aref (pos-boards position) colored-piece-code) (logandc2 (aref (pos-boards position) colored-piece-code) mask)
            (aref (pos-by-color position) color)           (logandc2 (aref (pos-by-color position) color) mask)
            (aref (pos-by-piece position) piece)           (logandc2 (aref (pos-by-piece position) piece) mask)
            ;; Update the occupancy bitboard (combined White + Black)
            (pos-occupied-squares position)                        (logandc2 (pos-occupied-squares position) mask))))
  position)

(defmacro with-position ((side occupied friendly enemy) position &body body)
  "Binds some necessary information about the position"
  (alexandria:with-gensyms (pos color-index)
    `(let* ((,pos        ,position)
            (,side     (pos-side-to-move ,pos))
            (,color-index      (color-index ,side))
            (,occupied (pos-occupied-squares ,pos))
            (,friendly (aref (pos-by-color ,pos) ,color-index))
            (,enemy    (aref (pos-by-color ,pos) (- 1 ,color-index))))
       (declare (ignorable ,occupied)
		(ignorable ,friendly)
		(ignorable ,enemy)
		(ignorable ,color-index))
       ,@body)))

(defun copy-position (pos)
  (make-position
    :boards           (copy-seq (pos-boards pos))
    :by-color         (copy-seq (pos-by-color pos))
    :by-piece         (copy-seq (pos-by-piece pos))
    :occupied-squares (pos-occupied-squares pos)
    :side-to-move     (pos-side-to-move pos)
    :castling         (pos-castling pos)
    :ep-square        (pos-ep-square pos)
    :halfmove-clock   (pos-halfmove-clock pos)
    :fullmove-number  (pos-fullmove-number pos)
    :hash             (pos-hash pos)))
