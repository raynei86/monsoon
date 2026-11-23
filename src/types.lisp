;;;; This file contains all the basic types that will be used in an engine:
;;;; squares, pieces, bitboards, things of that nature.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))
(declaim (inline sq file-of rank-of color-index piece-index colored-piece-index
                 piece-from-index colored-piece-code-piece colored-piece-code-color))

;; Squares and board
(deftype square ()
  "A chess board square. It's a number in the range [0, 63]"
  '(unsigned-byte 6))

(defun sq (name)
  "Translate a symbol like :e4 to its square index."
  (declare (type symbol name))
  (let* ((str (symbol-name name))
         (file (- (char-code (char-downcase (char str 0))) (char-code #\a)))
         (rank (1- (digit-char-p (char str 1)))))
    (+ (* rank 8) file)))


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
  "An integer in [0, 11] representing a piece and its color.
   The low bit is the color index (0 white, 1 black); the rest is
   the piece index. Produced by `colored-piece-index`."
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

(defun piece-from-index (idx)
  "Return the piece keyword for a piece index in [0, 5]."
  (declare (type (integer 0 5) idx))
  (ecase idx
    (0 :pawn) (1 :knight) (2 :bishop)
    (3 :rook) (4 :queen)  (5 :king)))

(defun colored-piece-code-piece (code)
  "Return the piece keyword of a colored-piece-code."
  (declare (type colored-piece-code code))
  (piece-from-index (ash code -1)))

(defun colored-piece-code-color (code)
  "Return the color keyword of a colored-piece-code."
  (declare (type colored-piece-code code))
  (if (logbitp 0 code) :black :white))

;; Hashing and utils
(deftype hash-key ()
  '(unsigned-byte 64))

;; Move representation
;; A move is a single fixnum packing from/to/promotion/flags:
;;   bits 0..5   from square
;;   bits 6..11  to square
;;   bits 12..14 promotion code (0 = none, 1 = queen, 2 = rook, 3 = bishop, 4 = knight)
;;   bits 15..19 flags
(defconstant +move-from-offset+         0)

(defconstant +move-to-offset+           6)

(defconstant +move-promotion-offset+    12)

(defconstant +move-flags-offset+        15)

(deftype move () '(unsigned-byte 20))

(declaim (inline move-from move-to move-promotion move-flags make-move
                 promotion-code code-to-promotion))

(defun promotion-code (promotion)
  "Encode a promotion piece (or NIL) as the 3-bit field value."
  (case promotion
    ((nil) 0) (:queen 1) (:rook 2) (:bishop 3) (:knight 4)))

(defun code-to-promotion (code)
  "Decode a 3-bit promotion field value into a piece keyword or NIL."
  (case code
    (0 nil) (1 :queen) (2 :rook) (3 :bishop) (4 :knight)))

(defun move-from (move)
  "The origin square of MOVE."
  (declare (type move move))
  (ldb (byte 6 +move-from-offset+) move))

(defun move-to (move)
  "The destination square of MOVE."
  (declare (type move move))
  (ldb (byte 6 +move-to-offset+) move))

(defun move-promotion (move)
  "The promotion piece of MOVE, or NIL."
  (declare (type move move))
  (code-to-promotion (ldb (byte 3 +move-promotion-offset+) move)))

(defun move-flags (move)
  "The flag bits of MOVE."
  (declare (type move move))
  (ldb (byte 5 +move-flags-offset+) move))

(defun make-move (from to &optional promotion flags)
  "Pack FROM, TO, PROMOTION, and FLAGS into a move."
  (declare (type square from to)
           (type (or null piece) promotion)
           (type (or null (unsigned-byte 5)) flags))
  (logior from
          (ash to +move-to-offset+)
          (ash (promotion-code promotion) +move-promotion-offset+)
          (ash (or flags 0) +move-flags-offset+)))

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

;;; Side parameters
;;; One record per color, indexed by COLOR-INDEX: everything that used to be
;;; an (if (eq side :white) ...) dispatch. Fields are explicit — PUSH-SHIFT
;;; points toward the opponent, PAWN-BACK-SHIFT points behind an advanced
;;; pawn — so no caller has to negate anything.

(defstruct (side-parameters (:conc-name side-))
  "Per-color movement and castling parameters."
  (push-shift       8 :type fixnum)   ; toward the opponent
  (pawn-back-shift -8 :type fixnum)   ; behind a pawn (EP square/victim)
  (cap-e-shift      9 :type fixnum)   ; east = toward file H
  (cap-w-shift      7 :type fixnum)
  (start-rank 0 :type bitboard)       ; rank a pawn may double-push from
  (promo-rank 0 :type bitboard)       ; rank a pawn promotes on
  (king-sq 0 :type square)
  (kingside-sq 0 :type square)
  (queenside-sq 0 :type square)
  (kingside-right 0 :type castling-rights)
  (queenside-right 0 :type castling-rights)
  (kingside-empty 0 :type bitboard)
  (queenside-empty 0 :type bitboard)
  (kingside-safe 0 :type bitboard)
  (queenside-safe 0 :type bitboard)
  (kingside-rook-from 0 :type square)
  (kingside-rook-to 0 :type square)
  (queenside-rook-from 0 :type square)
  (queenside-rook-to 0 :type square))

(defun make-side-parameters-table ()
  "Build the white/black parameter vector. Load-time only: it calls SQ."
  (vector
   (make-side-parameters
    :push-shift 8 :pawn-back-shift -8 :cap-e-shift 9 :cap-w-shift 7
    :start-rank +rank-2+ :promo-rank +rank-8+
    :king-sq (sq :e1) :kingside-sq (sq :g1) :queenside-sq (sq :c1)
    :kingside-right +white-kingside+ :queenside-right +white-queenside+
    :kingside-rook-from (sq :h1) :kingside-rook-to (sq :f1)
    :queenside-rook-from (sq :a1) :queenside-rook-to (sq :d1)
    :kingside-empty (logior (ash 1 (sq :f1)) (ash 1 (sq :g1)))
    :queenside-empty (logior (ash 1 (sq :b1)) (ash 1 (sq :c1)) (ash 1 (sq :d1)))
    :kingside-safe (logior (ash 1 (sq :f1)) (ash 1 (sq :g1)))
    :queenside-safe (logior (ash 1 (sq :c1)) (ash 1 (sq :d1))))
   (make-side-parameters
    :push-shift -8 :pawn-back-shift 8 :cap-e-shift -7 :cap-w-shift -9
    :start-rank +rank-7+ :promo-rank +rank-1+
    :king-sq (sq :e8) :kingside-sq (sq :g8) :queenside-sq (sq :c8)
    :kingside-right +black-kingside+ :queenside-right +black-queenside+
    :kingside-rook-from (sq :h8) :kingside-rook-to (sq :f8)
    :queenside-rook-from (sq :a8) :queenside-rook-to (sq :d8)
    :kingside-empty (logior (ash 1 (sq :f8)) (ash 1 (sq :g8)))
    :queenside-empty (logior (ash 1 (sq :b8)) (ash 1 (sq :c8)) (ash 1 (sq :d8)))
    :kingside-safe (logior (ash 1 (sq :f8)) (ash 1 (sq :g8)))
    :queenside-safe (logior (ash 1 (sq :c8)) (ash 1 (sq :d8))))))

(defparameter +side-parameters+ (make-side-parameters-table)
  "Per-color parameters indexed by COLOR-INDEX. A DEFPARAMETER, not a
   DEFCONST: its initializer calls SQ, which is not available while this
   file is still compiling.")

(declaim (type (simple-vector 2) +side-parameters+))

(declaim (inline side-params))

(declaim (ftype (function (color) side-parameters) side-params))

(defun side-params (side)
  "The movement and castling parameters for SIDE."
  (declare (type color side))
  (svref +side-parameters+ (color-index side)))
