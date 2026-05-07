;; FEN related stuff, not sure if it deserves its own file yet but it
;; will for now.

(in-package #:monsoon)

(defun fen-char->piece (ch)
  (ecase (char-downcase ch)
    (#\p :pawn) (#\n :knight) (#\b :bishop)
    (#\r :rook) (#\q :queen)  (#\k :king)))

(defun fen-char->color (ch)
  (if (upper-case-p ch) :white :black))

(defmacro with-fen-fields ((placement side castling ep halfmove fullmove) fen &body body)
  "Destructure the six fields of a FEN string into named bindings."
  `(destructuring-bind (,placement ,side ,castling ,ep ,halfmove ,fullmove)
       (serapeum:tokens ,fen)
     ,@body))

;; TODO: This is probably useful elsewhere too
(defun place-piece! (pos square piece color)
  "Place `piece` of `color` on `square`, updating all boards."
  (let ((bit (ash 1 square))
        (piece  (piece-index piece))
        (color  (color-index color))
        (color-piece (colored-piece-index piece color)))
    (setf (aref (pos-boards   pos) color-piece)    (logior (aref (pos-boards   pos) color-piece) bit)
          (aref (pos-by-piece pos) piece)          (logior (aref (pos-by-piece pos) piece)  bit)
          (aref (pos-by-color pos) color)          (logior (aref (pos-by-color pos) color)  bit)
          (pos-occupied-squares pos)               (logior (pos-occupied-squares pos)    bit))))

(defun parse-placement! (pos placement-str)
  (it:iter
    (it:with rank = 7)   ; FEN starts from rank 8 (index 7) and descends
    (it:with file = 0)
    (it:for ch in-sequence placement-str)
    (cond
      ((char= ch #\/)    (setf file 0) (decf rank))
      ((digit-char-p ch) (incf file (digit-char-p ch)))
      (t
       (place-piece! pos (+ (* rank 8) file)
                     (fen-char->piece ch)
                     (fen-char->color ch))
       (incf file)))))

(defun parse-side (side-str)
  (if (string= side-str "w") :white :black))

(defun parse-castling (castling-str)
  (it:iter
    (it:for ch in-sequence castling-str)
    (it:sum (case ch
              (#\K +white-kingside+)  (#\Q +white-queenside+)
              (#\k +black-kingside+)  (#\q +black-queenside+)
              (t 0)))))

(defun parse-ep-square (ep-str)
  (unless (string= ep-str "-")
    ;; `sq` only takes keywords, so need a small hack here
    (sq (intern (string-upcase ep-str) :keyword))))

(defun position-from-fen (fen)
  "Constructs a position from a FEN string"
  (with-fen-fields (placement side castling ep halfmove fullmove) fen
    (let ((pos (make-position)))
      (parse-placement! pos placement)
      (setf (pos-side-to-move    pos) (parse-side     side)
            (pos-castling        pos) (parse-castling castling)
            (pos-ep-square       pos) (parse-ep-square ep)
            (pos-halfmove-clock  pos) (parse-integer  halfmove)
            (pos-fullmove-number pos) (parse-integer  fullmove))
      pos)))
