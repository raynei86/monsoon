;;;; Castling geometry: squares, paths, rights, and per-side parameters.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))

;; Castling move generation
;; One named square constant per side.
(defconst +white-king-sq+              (sq :e1))

(defconst +white-kingside-sq+          (sq :g1))

(defconst +white-queenside-sq+         (sq :c1))

(defconst +white-kingside-rook-from+   (sq :h1))

(defconst +white-kingside-rook-to+     (sq :f1))

(defconst +white-queenside-rook-from+  (sq :a1))

(defconst +white-queenside-rook-to+    (sq :d1))

(defconst +white-queenside-rook-passage+ (sq :b1))

(defconst +black-king-sq+              (sq :e8))

(defconst +black-kingside-sq+          (sq :g8))

(defconst +black-queenside-sq+         (sq :c8))

(defconst +black-kingside-rook-from+   (sq :h8))

(defconst +black-kingside-rook-to+     (sq :f8))

(defconst +black-queenside-rook-from+  (sq :a8))

(defconst +black-queenside-rook-to+    (sq :d8))

(defconst +black-queenside-rook-passage+ (sq :b8))

;; Squares that must be empty for the rook and king to pass through.
(defconst +white-kingside-empty-squares+  (logior (ash 1 +white-kingside-rook-to+) (ash 1 +white-kingside-sq+)))

(defconst +white-queenside-empty-squares+ (logior (ash 1 +white-queenside-rook-passage+) (ash 1 +white-queenside-rook-to+) (ash 1 +white-queenside-sq+)))

(defconst +black-kingside-empty-squares+  (logior (ash 1 +black-kingside-rook-to+) (ash 1 +black-kingside-sq+)))

(defconst +black-queenside-empty-squares+ (logior (ash 1 +black-queenside-rook-passage+) (ash 1 +black-queenside-rook-to+) (ash 1 +black-queenside-sq+)))

;; Squares the king must not be in check on (its transit square + destination).
(defconst +white-kingside-safe-squares+  (logior (ash 1 +white-kingside-rook-to+) (ash 1 +white-kingside-sq+)))

(defconst +white-queenside-safe-squares+ (logior (ash 1 +white-queenside-rook-to+) (ash 1 +white-queenside-sq+)))

(defconst +black-kingside-safe-squares+  (logior (ash 1 +black-kingside-rook-to+) (ash 1 +black-kingside-sq+)))

(defconst +black-queenside-safe-squares+ (logior (ash 1 +black-queenside-rook-to+) (ash 1 +black-queenside-sq+)))

(defun castling-safe-squares (side flags)
  "Return the squares the king must not be in check on for a castling move."
  (declare (type color side)
           (type (unsigned-byte 5) flags))
  (let ((kingside-p (logtest flags +move-flag-kingside+)))
    (if (eq side :white)
        (if kingside-p +white-kingside-safe-squares+ +white-queenside-safe-squares+)
        (if kingside-p +black-kingside-safe-squares+ +black-queenside-safe-squares+))))

(defmacro with-castling-params (side &body body)
  "Bind the castling rights, empty squares, and destination/rook squares for SIDE.
   Empty squares must be clear for the rook and king to pass; safe squares are
   the squares the king must not be in check on."
  `(let ((kingside-right  (if (eq ,side :white) +white-kingside+  +black-kingside+))
         (queenside-right (if (eq ,side :white) +white-queenside+ +black-queenside+))
         (kingside-empty-squares  (if (eq ,side :white) +white-kingside-empty-squares+  +black-kingside-empty-squares+))
         (queenside-empty-squares (if (eq ,side :white) +white-queenside-empty-squares+ +black-queenside-empty-squares+))
         (king-sq         (if (eq ,side :white) +white-king-sq+ +black-king-sq+))
         (kingside-sq     (if (eq ,side :white) +white-kingside-sq+ +black-kingside-sq+))
         (queenside-sq    (if (eq ,side :white) +white-queenside-sq+ +black-queenside-sq+))
         (kingside-rook-from  (if (eq ,side :white) +white-kingside-rook-from+  +black-kingside-rook-from+))
         (kingside-rook-to    (if (eq ,side :white) +white-kingside-rook-to+    +black-kingside-rook-to+))
         (queenside-rook-from (if (eq ,side :white) +white-queenside-rook-from+ +black-queenside-rook-from+))
         (queenside-rook-to   (if (eq ,side :white) +white-queenside-rook-to+   +black-queenside-rook-to+)))
     (declare (ignorable kingside-right queenside-right
                         kingside-empty-squares queenside-empty-squares
                         king-sq kingside-sq queenside-sq
                         kingside-rook-from kingside-rook-to
                         queenside-rook-from queenside-rook-to))
     ,@body))

(declaim (ftype (function (color (unsigned-byte 5)) bitboard) castling-safe-squares))
