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

; These guys come in a pair
(deftype file () '(integer 0 7))
(deftype rank () '(integer 0 7))

(defun file-of (square)
  (declare (type square square))
  (mod square 8))

(defun rank-of (square)
  (declare (type square square))
  (values (floor square 8)))

;; Pieces and color
(deftype color ()
  "Either :white or :black, use as you see fit."
  '(member :white :black))

(deftype piece ()
  "One of the six kinds of chess pieces."
  '(member :pawn :knight :bishop :rook :queen :king))

(defun color-code (color)
  "Returns 0 for white, 1 for black"
  (declare (type color color))
  (if (eq color :white) 0 1))

(defun piece-code (piece)
  "Returns an integer [0, 5] representing the piece."
  (declare (type piece piece))
  (ecase piece
    (:pawn 0) (:knight 1) (:bishop 2)
    (:rook 3) (:queen 4) (:king 5)))

(defun colored-piece-code (piece color)
  "Returns an integer [0, 11] representing a colored piece."
  (declare (type piece piece)
	   (type color color))
  (+ (* (piece-code piece) 2) (color-code color)))
