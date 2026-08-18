;;;; Playground for macros and funky stuff

(in-package :monsoon)

(declaim (optimize (speed 3) (safety 1)))
(declaim (inline lsb msb))

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
