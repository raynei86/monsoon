;;;; Playground for macros and funky stuff

(in-package :monsoon)

(declaim (inline lsb msb))

;; Bits related utils
(defun lsb (bb)
  (declare (type bitboard bb))
  (1- (integer-length (logand bb (- bb)))))

(defun msb (bb)
  (declare (type bitboard bb))
  (1- (integer-length bb)))

(it:defmacro-clause (FOR bit in-bitboard bitboard)
  "Iterates over the individual bits of a bitboard"
  (alexandria:with-gensyms (bb)
    `(progn
       (it:with ,bb = ,bitboard)
       (it:for ,bit = (if (zerop ,bb)
			  (it:terminate)
			  (lsb ,bb)))
       (it:after-each (setf ,bb (logand ,bb (1- ,bb)))))))
