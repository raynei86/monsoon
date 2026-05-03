;;;; The dreaded move generation. Prepare for some blasphemous and
;;;; ugly code.

(in-package #:monsoon)

;; Types and declarations 
(defstruct (move (:constructor make-move (from to &optional promotion flags)))
  (from 0 :type square)
  (to 0 :type square)
  (promotion nil :type (or null piece))
  (flags 0 :type (unsigned-byte 5)))

(serapeum:defconst +move-flag-capture+   #b00001)
(serapeum:defconst +move-flag-double+    #b00010)
(serapeum:defconst +move-flag-ep+        #b00100)
(serapeum:defconst +move-flag-kingside+  #b01000)
(serapeum:defconst +move-flag-queenside+ #b10000)

(defun move-has-flag? (move flag-keyword)
  "A neat wrapper to avoid bit fiddling
   The flags are:
   - :capture
   - :double
   - :ep
   - :kingside
   - :queenside"
  (declare (type move move) (type keyword flag-keyword))
  (logtest (move-flags move)
           (ecase flag-keyword
             (:capture   +move-flag-capture+)
             (:double    +move-flag-double+)
             (:ep        +move-flag-ep+)
             (:kingside  +move-flag-kingside+)
             (:queenside +move-flag-queenside+))))


;; Attack tables
(defmacro generate-attack-table (offsets check-move)
  `(it:iter
    (it:with table = (make-array 64 :element-type 'bitboard :initial-element 0))
    (it:for sq from 0 below 64)
    (setf (aref table sq)
	  (it:iter
	    (it:for offset in ,offsets)
	    (it:for to = (+ sq offset))
	    (when (and (<= 0 to 63) (,check-move sq to))
	      (it:sum (ash 1 to) into attacks))
	    (it:finally (return attacks))))
    (it:finally (return table))))

(serapeum:defconst +king-attacks+
  (generate-attack-table '(-9 -8 -7 -1 1 7 8 9) check-king-move))

(serapeum:defconst +knight-attacks+
  (generate-attack-table '(-17 -15 -10 -6 6 10 15 17) check-knight-move))

(defun check-knight-move (from to)
  (let ((df (abs (- (file-of from) (file-of to))))
	(dr (abs (- (rank-of from) (rank-of to)))))
    ;; Makes sure that file and rank difference cannot both be 2, or
    ;; else the knight went into a wormhole
    (or (and (= df 1) (= dr 2))
	(and (= dr 1) (= df 2)))))

(defun check-king-move (from to)
  (let ((df (abs (- (file-of to) (file-of from)))))
    ;; If the king managed to move more than 1 file, it most
    ;; definitely warped away
    (<= df 1)))


