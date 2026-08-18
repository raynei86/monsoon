;;;; This file contains all the basic types that will be used in an engine:
;;;; squares, pieces, bitboards, things of that nature.

(in-package #:monsoon)

(declaim (inline file-of rank-of color-index piece-index colored-piece-index))

;; Squares and board
(deftype square ()
  "A chess board square. It's a number in the range [0, 63]"
  '(unsigned-byte 6))

(defmacro sq (name)
  "Translates a symbol like :e4 to an integer like 28"
  (when (symbolp name)
      (let* ((str (symbol-name name))
             (file (- (char-code (char-downcase (char str 0))) (char-code #\a)))
             (rank (1- (digit-char-p (char str 1)))))
        (+ (* rank 8) file))))


(deftype bitboard ()
  "A bitboard represented using a 64-bit integer."
  '(unsigned-byte 64))

(defconst +full-board+ #xFFFFFFFFFFFFFFFF)
(defconst +rank-1+ #x00000000000000FF)
(defconst +rank-2+ #x000000000000FF00)
(defconst +rank-4+ #x00000000FF000000)
(defconst +rank-5+ #x000000FF00000000)
(defconst +rank-7+ #x00FF000000000000)
(defconst +rank-8+ #xFF00000000000000)
(defconst +not-file-a+ #xFEFEFEFEFEFEFEFE)
(defconst +not-file-h+ #x7F7F7F7F7F7F7F7F)

(deftype castling-rights ()
  "4 bits to represent castling rights."
  '(unsigned-byte 4))

(defconst +white-kingside+  #b1000)
(defconst +white-queenside+ #b0100)
(defconst +black-kingside+  #b0010)
(defconst +black-queenside+ #b0001)

(defconst +castling-rights-mask+
  ;; ANDed with current rights when a piece moves from or to that square.
  ;; All other squares have #b1111 as a no-op
  (let ((table (make-array 64 :initial-element #b1111)))
    (setf (aref table (sq :e1)) #b0011   ; white king: clears both white rights
          (aref table (sq :e8)) #b1100   ; black king: clears both black rights
          (aref table (sq :h1)) #b0111   ; white h-rook: clears white kingside
          (aref table (sq :a1)) #b1011   ; white a-rook: clears white queenside
          (aref table (sq :h8)) #b1101   ; black h-rook: clears black kingside
          (aref table (sq :a8)) #b1110)  ; black a-rook: clears black queenside
    table))

(deftype file () '(integer 0 7))
(deftype rank () '(integer 0 7))

(defun file-of (square)
  "Return the file index for SQUARE."
  (declare (type square square))
  (mod square 8))

(defun rank-of (square)
  "Return the rank index for SQUARE."
  (declare (type square square))
  (values (floor square 8)))


;; Pieces and color
(deftype color ()
  "Either :white or :black, use as you see fit."
  '(member :white :black))

(deftype piece ()
  "One of the six kinds of chess pieces."
  '(member :pawn :knight :bishop :rook :queen :king))

(deftype colored-piece-code ()
  "An integer representing a piece and its color"
  '(unsigned-byte 4))

(defun color-index (color)
  "Returns 0 for white, 1 for black"
  (declare (type color color))
  (if (eq color :white) 0 1))

(defun piece-index (piece)
  "Returns an integer [0, 5] representing the piece."
  (declare (type piece piece))
  (ecase piece
    (:pawn 0) (:knight 1) (:bishop 2)
    (:rook 3) (:queen 4) (:king 5)))

(defun colored-piece-index (piece color)
  "Returns an integer [0, 11] representing a colored piece."
  (declare (type piece piece)
	   (type color color))
  (+ (* (piece-index piece) 2) (color-index color)))

(defun decompose-colored-piece-index (index)
  "Return the piece index and color index from INDEX."
  (declare (type colored-piece-code index))
  (let* ((color (logand index 1))
         (piece (ash index -1)))
    (values piece color)))
(defmacro with-colored-piece-index ((piece color) index &body body)
  `(multiple-value-bind (,piece ,color)
       (decompose-colored-piece-index ,index)
     ,@body))

;; Hashing and utils
(deftype hash-key ()
  '(unsigned-byte 64))
