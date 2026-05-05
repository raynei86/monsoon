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
(defun direction-to-offset (direction)
  (case direction
    (:n 8)   (:s -8)  (:e 1)   (:w -1)
    (:ne 9)  (:nw 7)  (:se -7) (:sw -9)

    ;; Knight specific moves defined as combinations
    (:nne 17) (:nee 10) (:see -6) (:sse -15)
    (:ssw -17) (:sww -10) (:nww 6) (:nnw 15)))

(defmacro offsets (&rest dirs)
  "Translates compass keywords to a list of integer offsets."
  `(list ,@(mapcar #'direction-to-offset dirs)))

(defmacro generate-attack-table (directions &body check-logic)
  `(it:iter
     (it:with table = (make-array 64 :element-type 'bitboard :initial-element 0))
     (it:for sq from 0 below 64)
     (setf (aref table sq)
	   (it:iter
	     (it:for offset in (offsets ,@ directions))
	     (it:for to = (+ sq offset))
	     (when (and (<= 0 to 63)
			(let ((from sq) (to to)) ,@check-logic))
	       (it:sum (ash 1 to) into attacks))
	     (it:finally (return attacks))))
     (it:finally (return table))))

(serapeum:defconst +king-attacks+
  (generate-attack-table (:n :s :e :w :ne :nw :se :sw)
    (<= (abs (- (file-of from) (file-of to))) 1))) 

(serapeum:defconst +knight-attacks+
  (generate-attack-table (:nne :nee :see :sse :ssw :sww :nww :nnw)
    (let ((df (abs (- (file-of from) (file-of to))))
	  (dr (abs (- (rank-of from) (rank-of to)))))
      (or (and (= df 1) (= dr 2))
	  (and (= dr 1) (= df 2))))))

;; Rays and sliding pieces
(defmacro generate-ray-table (direction)
  "Creates an attack table for rays going in that direction, ignoring attackers"
  (let ((offset (direction-to-offset direction)))
    `(it:iter
       (it:with table = (make-array 64 :element-type 'bitboard :initial-element 0))
       (it:for sq from 0 below 64)
       (setf (aref table sq)
	     (it:iter
	       (it:for current initially sq then next)
	       (it:for next = (+ current ,offset))
	       (it:while (and (<= 0 next 63)
			      (<= (abs (- (file-of next) (file-of current))) 1)))
	       (it:sum (ash 1 next) into ray)
	       (it:finally (return ray))))
       (it:finally (return table)))))

(serapeum:defconst +rays+
  (list (cons :n (generate-ray-table :n))  (cons :ne (generate-ray-table :ne))
	(cons :e (generate-ray-table :e))  (cons :se (generate-ray-table :se))
	(cons :s (generate-ray-table :s))  (cons :sw (generate-ray-table :sw))
	(cons :w (generate-ray-table :w))  (cons :nw (generate-ray-table :nw))))

(defmacro ray (direction square)
  "Look up the precomputed ray mask for direction at a square"
  `(aref (cdr (assoc ,direction +rays+)) ,square))

(defmacro ray-attacks (square direction occupied blocker-func)
  "Takes a square, direction of the ray, and a bitboard of occupied squares.
   Then returns a ray that factors in obstacles."
  `(let* ((ray (ray ,direction ,square))
	 (blockers (logand ray ,occupied))) ; All occupied squares on ray path
    (if (zerop blockers)
	ray
					; When there is a blocker, cut off the ray by xoring it with
					; another ray at the obstacle
	(logxor ray (ray ,direction (,blocker-func blockers))))))

(defun ray-attacks+ (sq direction occupied)
  "Attacks along a positive ray from square, cut off at first obstacle"
  (ray-attacks sq direction occupied lsb))

(defun ray-attacks- (sq direction occupied)
  "Attacks along a negative ray from square, cut off at first obstacle"
  (ray-attacks sq direction occupied msb))
