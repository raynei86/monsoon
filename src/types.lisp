;;;; This file contains all the basic types that will be used in an engine:
;;;; squares, pieces, bitboards, things of that nature.

(in-package #:monsoon)

;; Squares and board
(deftype square ()
  "A chess board square. It's a number in the range [0, 64]"
  '(mod 64))

(deftype bitboard ()
  "A bitboard represented using a 64bit integer."
  '(unsigned-byte 64))

(serapeum:defconst +full-board+ #xFFFFFFFFFFFFFFFF)
(serapeum:defconst +rank-1+ #x00000000000000FF)
(serapeum:defconst +rank-2+ #x000000000000FF00)
(serapeum:defconst +rank-4+ #x00000000FF000000)
(serapeum:defconst +rank-5+ #x000000FF00000000)
(serapeum:defconst +rank-7+ #x00FF000000000000)
(serapeum:defconst +rank-8+ #xFF00000000000000)
(serapeum:defconst +not-file-a+ #xFEFEFEFEFEFEFEFE)
(serapeum:defconst +not-file-h+ #x7F7F7F7F7F7F7F7F)

(deftype castling-rights ()
  "4 bits to represent castling rights."
  '(unsigned-byte 4))

(serapeum:defconst +white-kingside+  #b1000)
(serapeum:defconst +white-queenside+ #b0100)
(serapeum:defconst +black-kingside+  #b0010)
(serapeum:defconst +black-queenside+ #b0001)

(deftype file () '(integer 0 7))
(deftype rank () '(integer 0 7))

(defun file-of (square)
  (declare (type square square))
  (mod square 8))

(defun rank-of (square)
  (declare (type square square))
  (values (floor square 8)))

(defmacro sq (name)
  "Translates a symbol like :e4 to an integer like 28"
  (when (symbolp name)
      (let* ((str (symbol-name name))
             (file (- (char-code (char-downcase (char str 0))) (char-code #\a)))
             (rank (1- (digit-char-p (char str 1)))))
        (+ (* rank 8) file))))


;; Pieces and color
(deftype color ()
  "Either :white or :black, use as you see fit."
  '(member :white :black))

(deftype piece ()
  "One of the six kinds of chess pieces."
  '(member :pawn :knight :bishop :rook :queen :king))

(deftype colored-piece-code ()
  "An integer representing a piece and its color"
  '(integer 0 11))

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
  (declare (type colored-piece-code index))
  (let* ((color (if (evenp index) 0 1))
	 (piece (/ (- index color) 2)))
    (values piece color)))
(defmacro with-colored-piece-index ((piece color) index &body body)
  `(multiple-value-bind (,piece ,color)
       (decompose-colored-piece-index ,index)
     ,@body))

;; Hashing and utils
(deftype hash-key ()
  '(unsigned-byte 64))
