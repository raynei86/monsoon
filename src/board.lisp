;;;; The meat, the heart, the board representation that will be used
;;;; by the library. Each position is represented using the standard
;;;; bitboard approach with all the neat info tacked inside.

(in-package #:monsoon)

(defstruct (position (:conc-name pos-))
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

  (mailbox			; To make square-centric lookup easier
   (make-array 64 :element-type 'colored-piece-code :initial-element 0)
   :type (simple-array colored-piece-code (64)))
  
  (occupied-squares   ; Union of the two colored bitboards
   0
   :type bitboard)

  (side-to-move :white :type color)
  (castling     0   :type castling-rights)
  (ep-square    nil   :type (or null square))
  (halfmove-clock 0   :type (integer 0 100))
  (fullmove-number 1   :type (integer 1 *))
  (hash         0   :type hash-key))  ; Zobrist hash not implemented yet, keep it for now

(defun occupant-at (pos square)
  "Returns the colored piece at that square as an `color-pieced-code`"
  (aref (pos-mailbox pos) square))

(defun piece-at (pos square)
  "Returns the type of piece at that square"
  (piece-index (occupant-at pos square)))

(defun color-at (pos square)
  "Returns the color of the piece at that square"
  (color-index (occupant-at pos square)))

(defun opponent (color)
  (declare (type color color))
  (if (eq color :white) :black :white))

(defmacro with-position ((side occupied friendly enemy) position &body body)
  "Binds some necessary information about the position"
  (alexandria:with-gensyms (pos color-index)
    `(let* ((,pos        ,position)
            (,side     (pos-side-to-move ,pos))
            (,color-index      (color-index ,side))
            (,occupied (pos-occupied-squares ,pos))
            (,friendly (aref (pos-by-color ,pos) ,color-index))
            (,enemy    (aref (pos-by-color ,pos) (- 1 ,color-index))))
       ,@body)))
