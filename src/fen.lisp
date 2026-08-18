;; FEN parsing helpers.

(in-package #:monsoon)

(defun fen-char->piece (ch)
  "Return the piece keyword represented by CH."
  (ecase (char-downcase ch)
    (#\p :pawn) (#\n :knight) (#\b :bishop)
    (#\r :rook) (#\q :queen)  (#\k :king)))

(defun fen-char->color (ch)
  "Return the piece color represented by CH."
  (if (upper-case-p ch) :white :black))

(defmacro with-fen-fields ((placement side castling ep halfmove fullmove) fen &body body)
  "Destructure the six fields of a FEN string into named bindings."
  `(destructuring-bind (,placement ,side ,castling ,ep ,halfmove ,fullmove)
       (tokens ,fen)
     ,@body))

(defun parse-placement! (pos placement-str)
  "Populate POS with pieces from PLACEMENT-STR."
  (iter
    (with rank = 7)   ; FEN starts from rank 8 (index 7) and descends
    (with file = 0)
    (for ch in-sequence placement-str)
    (cond
      ((char= ch #\/)    (setf file 0) (decf rank))
      ((digit-char-p ch) (incf file (digit-char-p ch)))
      (t
       (place-piece! pos (+ (* rank 8) file)
                     (colored-piece-index (fen-char->piece ch)
					  (fen-char->color ch)))
       (incf file)))))

(defun parse-side (side-str)
  "Parse SIDE-STR into :white or :black."
  (if (string= side-str "w") :white :black))

(defun parse-castling (castling-str)
  "Parse CASTLING-STR into castling rights."
  (iter
    (for ch in-sequence castling-str)
    (sum (case ch
              (#\K +white-kingside+)  (#\Q +white-queenside+)
              (#\k +black-kingside+)  (#\q +black-queenside+)
              (t 0)))))

(defun parse-ep-square (ep-str)
  "Parse EP-STR into a square or NIL."
  (unless (string= ep-str "-")
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
