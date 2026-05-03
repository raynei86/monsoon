;;;; The dreaded move generation. Prepare for some blasphemous and
;;;; ugly code.

(in-package #:monsoon)

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

