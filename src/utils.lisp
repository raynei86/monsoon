;;;; Playground for macros and funky stuff

(in-package :monsoon)

(declaim (optimize (speed 3) (safety 1)))
(declaim (inline lsb msb))
(declaim (ftype (function (bitboard) (integer -1 63)) lsb msb))

;; Bits related utils
(defun lsb (bb)
  "Return the index of the least significant set bit in BB."
  (declare (type bitboard bb))
  (1- (integer-length (logand bb (- bb)))))

(defun msb (bb)
  "Return the index of the most significant set bit in BB."
  (declare (type bitboard bb))
  (1- (integer-length bb)))

(defmacro-clause (FOR bit in-bitboard bitboard)
  "Iterates over the individual bits of a bitboard"
  (with-gensyms (bb)
    `(progn
       (with ,bb = ,bitboard)
       (for ,bit = (if (zerop ,bb)
			  (terminate)
			  (lsb ,bb)))
       (after-each (setf ,bb (logand ,bb (1- ,bb)))))))

(defmacro do-bitboard ((bit bitboard &optional result) &body body)
  "Iterates over the individual set bits of a bitboard, binding BIT to each LSB."
  (let ((bb (gensym "BB-")))
    `(do ((,bb ,bitboard (logand ,bb (1- ,bb))))
         ((zerop ,bb) ,result)
       (let ((,bit (lsb ,bb)))
         ,@body))))
