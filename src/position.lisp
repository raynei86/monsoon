;;;; The meat, the heart, the board representation that will be used
;;;; by the library. Each position is represented using the standard
;;;; bitboard approach with all the neat info tacked inside.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))
(declaim (inline occupied-p color-at piece-at occupant-at place-piece! remove-piece! opponent))

(defstruct (position (:conc-name pos-)
		     (:copier nil))
  "A chess position. What more do you expect?"

  (boards     ; The 12 bitboards for both each different colored piece
   (make-array 12 :element-type 'bitboard :initial-element 0)
   :type (simple-array bitboard (12)))

  (by-color   ; Colored bitboard, shows squares occupied by each color
   (make-array 2 :element-type 'bitboard :initial-element 0)
   :type (simple-array bitboard (2)))

  (occupied-squares		  ; Union of the two colored bitboards
   0
   :type bitboard)

  (side-to-move :white :type color)
  (castling     0   :type castling-rights)
  (ep-square    nil   :type (or null square))
  (halfmove-clock 0   :type (unsigned-byte 7))
  (fullmove-number 1   :type fixnum)
  ;; Reserved for Zobrist hashing (not implemented yet).
  (hash         0   :type hash-key))

(defun occupied-p (position square)
  "Return true if SQUARE is occupied in POSITION."
  (declare (type square square))
  (logbitp square (pos-occupied-squares position)))

(defun color-at (position square)
  "Returns the color of the piece on `square`. Assumes the square is occupied."
  (declare (type square square))
  (if (logbitp square (aref (pos-by-color position) 0))
      :white
      (if (logbitp square (aref (pos-by-color position) 1))
	  :black
	  nil)))

(defun piece-at (position square)
  "Returns the piece type on `square`. Assumes the square is occupied."
  (declare (type square square))
  (let* ((color (color-at position square))
         (boards (pos-boards position)))
    (cond
      ((logbitp square (aref boards (colored-piece-index :pawn   color))) :pawn)
      ((logbitp square (aref boards (colored-piece-index :knight color))) :knight)
      ((logbitp square (aref boards (colored-piece-index :bishop color))) :bishop)
      ((logbitp square (aref boards (colored-piece-index :rook   color))) :rook)
      ((logbitp square (aref boards (colored-piece-index :queen  color))) :queen)
      ((logbitp square (aref boards (colored-piece-index :king   color))) :king))))

(defun occupant-at (position square)
  "Return the piece and color at SQUARE, or NIL values if empty."
  (if (occupied-p position square)
      (values (piece-at  position square)
              (color-at position square))
      (values nil nil)))

(defmacro with-square ((piece color) position square &body body)
  "Bind `piece` and `color` for the occupant of `square` in `position`.
   Both are NIL if the square is empty."
  `(multiple-value-bind (,piece ,color)
       (occupant-at ,position ,square)
     ,@body))

(defun opponent (color)
  "Return the opposing color."
  (declare (type color color))
  (if (eq color :white) :black :white))

(defun place-piece! (position square colored-piece-code)
  "Adds a piece to the board and updates all tracking bitboards."
  (declare (type position position) (type square square))
  (let ((mask  (ash 1 square))
        (color (logand colored-piece-code 1)))
    (setf (aref (pos-boards position) colored-piece-code) (logior (aref (pos-boards position) colored-piece-code) mask)
          (aref (pos-by-color position) color)            (logior (aref (pos-by-color position) color) mask)
          ;; Update the occupancy bitboard (combined White + Black)
          (pos-occupied-squares position)                        (logior (pos-occupied-squares position) mask)))
  position)

(defun remove-piece! (position square colored-piece-code)
  "Clears a piece from the board and updates all tracking bitboards."
  (declare (type position position) (type square square))
  (let ((mask  (ash 1 square))
        (color (logand colored-piece-code 1)))
    (setf (aref (pos-boards position) colored-piece-code) (logandc2 (aref (pos-boards position) colored-piece-code) mask)
          (aref (pos-by-color position) color)            (logandc2 (aref (pos-by-color position) color) mask)
          ;; Update the occupancy bitboard (combined White + Black)
          (pos-occupied-squares position)                        (logandc2 (pos-occupied-squares position) mask)))
  position)

(defmacro with-position ((side occupied friendly enemy) position &body body)
  "Binds some necessary information about the position"
  (let ((pos (gensym "POS-"))
        (color-idx (gensym "COLOR-IDX-")))
    `(let* ((,pos        ,position)
            (,side     (pos-side-to-move ,pos))
            (,color-idx      (color-index ,side))
            (,occupied (pos-occupied-squares ,pos))
            (,friendly (aref (pos-by-color ,pos) ,color-idx))
            (,enemy    (aref (pos-by-color ,pos) (- 1 ,color-idx))))
       (declare (ignorable ,occupied)
		(ignorable ,friendly)
		(ignorable ,enemy)
		(ignorable ,color-idx))
       ,@body)))

(defun copy-position (pos)
  "Return a copy of POS with duplicated arrays."
  (make-position
    :boards           (copy-seq (pos-boards pos))
    :by-color         (copy-seq (pos-by-color pos))
    :occupied-squares (pos-occupied-squares pos)
    :side-to-move     (pos-side-to-move pos)
    :castling         (pos-castling pos)
    :ep-square        (pos-ep-square pos)
    :halfmove-clock   (pos-halfmove-clock pos)
    :fullmove-number  (pos-fullmove-number pos)
    :hash             (pos-hash pos)))

(defun do-move! (position move)
  "Apply MOVE to POSITION in place.
   Returns (values MOVING-CPC CAPTURED-CPC OLD-CASTLING OLD-EP OLD-HALFMOVE
   OLD-FULLMOVE), the values UNDO-MOVE! needs to restore POSITION."
  (let* ((side (pos-side-to-move position))
         (opp (opponent side))
         (old-castling (pos-castling position))
         (old-ep (pos-ep-square position))
         (old-halfmove (pos-halfmove-clock position))
         (old-fullmove (pos-fullmove-number position)))
    (with-move (from to promotion flags) move
      (let ((captured-cpc
              (when (logtest flags +move-flag-capture+)
                (if (logtest flags +move-flag-ep+)
                    (colored-piece-index :pawn opp)
                    (colored-piece-index (piece-at position to) opp)))))
        (when captured-cpc
          (remove-piece! position
                         (if (logtest flags +move-flag-ep+)
                             (+ to (side-pawn-back-shift (side-params side)))
                             to)
                         captured-cpc))
        (let ((moving-cpc (colored-piece-index (piece-at position from) side)))
          (remove-piece! position from moving-cpc)
          (place-piece! position to moving-cpc)
          ;; If promotion just replace over it
          (when promotion
            (remove-piece! position to moving-cpc)
            (place-piece! position to (colored-piece-index promotion side)))
          ;; Castling: relocate the rook (castling moves only).
          (when (logtest flags (logior +move-flag-kingside+ +move-flag-queenside+))
            (let ((params (side-params side))
                  (rook-cpc (colored-piece-index :rook side)))
              (if (logtest flags +move-flag-kingside+)
                  (progn
                    (remove-piece! position (side-kingside-rook-from params) rook-cpc)
                    (place-piece!  position (side-kingside-rook-to params) rook-cpc))
                  (progn
                    (remove-piece! position (side-queenside-rook-from params) rook-cpc)
                    (place-piece!  position (side-queenside-rook-to params) rook-cpc)))))
          ;; Set the new en passant square on a double pawn push.
          (setf (pos-ep-square position)
                (when (logtest flags +move-flag-double+)
                  (+ to (side-pawn-back-shift (side-params side)))))
          ;; Update castling rights.
          (setf (pos-castling position)
                (logand old-castling
                        (logand (aref +castling-rights-mask+ from)
                                (aref +castling-rights-mask+ to))))
          ;; Halfmove clock: reset on pawn move or capture, otherwise increment.
          (setf (pos-halfmove-clock position)
                (if (or (eq :pawn (colored-piece-code-piece moving-cpc))
                        (logtest flags +move-flag-capture+))
                    0
                    (1+ old-halfmove)))
          ;; Fullmove number increments after black's reply.
          (when (eq side :black)
            (incf (pos-fullmove-number position)))
          ;; Flip the side to move.
          (setf (pos-side-to-move position) opp)
          (values moving-cpc captured-cpc old-castling old-ep
                  old-halfmove old-fullmove))))))

(defun undo-move! (position move moving-cpc captured-cpc
                   old-castling old-ep old-halfmove old-fullmove)
  "Reverse the effect of DO-MOVE! on POSITION."
  (let ((side (colored-piece-code-color moving-cpc)))
    (with-move (from to promotion flags) move
      ;; Move the piece back from TO to FROM, reversing any promotion.
      (remove-piece! position to
                     (if promotion
                         (colored-piece-index promotion side)
                         moving-cpc))
      (place-piece! position from moving-cpc)
      ;; Restore any captured piece (an EP victim sits behind TO).
      (when captured-cpc
        (place-piece! position
                      (if (logtest flags +move-flag-ep+)
                          (+ to (side-pawn-back-shift (side-params side)))
                          to)
                      captured-cpc))
      ;; Restore the rook relocated by castling.
      (when (logtest flags (logior +move-flag-kingside+ +move-flag-queenside+))
        (let ((params (side-params side))
              (rook-cpc (colored-piece-index :rook side)))
          (if (logtest flags +move-flag-kingside+)
              (progn
                (remove-piece! position (side-kingside-rook-to params) rook-cpc)
                (place-piece!  position (side-kingside-rook-from params) rook-cpc))
              (progn
                (remove-piece! position (side-queenside-rook-to params) rook-cpc)
                (place-piece!  position (side-queenside-rook-from params) rook-cpc)))))
      ;; Restore scalar state.
      (setf (pos-castling position) old-castling
            (pos-ep-square position) old-ep
            (pos-halfmove-clock position) old-halfmove
            (pos-fullmove-number position) old-fullmove
            (pos-side-to-move position) side))))

(defmacro with-move-applied ((position move) &body body)
  "Apply MOVE to POSITION in place, run BODY, then undo.
   POSITION is restored on exit, including non-local exits."
  (let ((m (gensym "M-"))
        (moving (gensym "MOVING-"))
        (captured (gensym "CAPTURED-"))
        (castling (gensym "CASTLING-"))
        (ep (gensym "EP-"))
        (halfmove (gensym "HALFMOVE-"))
        (fullmove (gensym "FULLMOVE-")))
    `(let ((,m ,move))
       (multiple-value-bind (,moving ,captured ,castling ,ep ,halfmove ,fullmove)
           (do-move! ,position ,m)
         (unwind-protect
              (progn ,@body)
           (undo-move! ,position ,m ,moving ,captured ,castling ,ep ,halfmove ,fullmove))))))

(defun do-move (position move)
  "Apply MOVE to POSITION and return the resulting position (a fresh copy)."
  (let ((new-pos (copy-position position)))
    (do-move! new-pos move)
    new-pos))
