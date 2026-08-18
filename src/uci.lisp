;;;; UCI protocol support

(in-package #:monsoon)

(serapeum:defconst +uci-startpos-fen+
  "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

(defstruct (uci-option (:constructor make-uci-option
                          (name type &key default min max vars)))
  (name "" :type string)
  (type :string :type keyword)
  (default nil)
  (min nil)
  (max nil)
  (vars nil))

(defstruct (uci-go-parameters (:conc-name uci-go-param-))
  searchmoves
  ponder
  wtime
  btime
  winc
  binc
  movestogo
  depth
  nodes
  mate
  movetime
  infinite)

(defclass uci-engine ()
  ((position
    :accessor uci-engine-position
    :initform (position-from-fen +uci-startpos-fen+))
   (option-values
    :accessor uci-engine-option-values
    :initform (make-hash-table :test #'equal))
   (debug
    :accessor uci-engine-debug
    :initform nil)))

(defgeneric uci-engine-name (engine)
  (:documentation "Return the engine name string sent in the UCI 'id name' response.
Subclasses should override this to return their own engine name."))

(defgeneric uci-engine-author (engine)
  (:documentation "Return the author name string sent in the UCI 'id author' response.
Subclasses should override this to return their own author name."))

(defgeneric uci-engine-options (engine)
  (:documentation "Return a list of UCI-OPTION structs describing the options this engine
supports. These are sent to the GUI after the 'id' lines in response to the 'uci' command.
The default implementation returns NIL (no options). Subclasses should override this to
advertise their own options."))

(defgeneric uci-new-game (engine)
  (:documentation "Called when the GUI sends 'ucinewgame', indicating that a new game is
starting. Engines should reset any game-specific state here (e.g. transposition tables,
hash history). The default implementation does nothing."))

(defgeneric uci-set-option (engine name value)
  (:documentation "Called when the GUI sends 'setoption name NAME value VALUE'. NAME is the
option name as a string (stored with downcased key); VALUE is the new value as a string, or
NIL if no value was provided. The default implementation stores the value in the engine's
option-values hash table keyed by the downcased name. Use UCI-GET-OPTION to retrieve stored
values."))

(defgeneric uci-position-updated (engine position)
  (:documentation "Called after the internal position has been updated by a 'position' command.
POSITION is the new POSITION object (same object already stored in the engine's
UCI-ENGINE-POSITION slot). This hook allows subclasses to react to position changes (e.g.
update incremental evaluators). The default implementation does nothing."))

(defgeneric uci-go (engine parameters)
  (:documentation "Called when the GUI sends a 'go' command. PARAMETERS is a UCI-GO-PARAMETERS
struct whose slots hold the search constraints (depth, movetime, wtime/btime, etc.). The method
must return two values: (1) the best move (a MOVE object, a UCI move string, or NIL to send
'bestmove 0000'), and (2) an optional ponder move or NIL. Subclasses must override this; the
default method signals an error."))

(defgeneric uci-stop (engine)
  (:documentation "Called when the GUI sends 'stop', requesting that the engine stop searching
as soon as possible and send a 'bestmove' response. Because UCI-GO is currently called
synchronously, this hook is invoked only after UCI-GO has already returned. Subclasses that
launch a background search thread should set a flag here to terminate the search. The default
implementation does nothing."))

(defgeneric uci-ponderhit (engine)
  (:documentation "Called when the GUI sends 'ponderhit', indicating that the position being
pondered has actually occurred on the board. The engine should switch from pondering mode to
normal timed search. Because UCI-GO is currently called synchronously, this hook is invoked
only after UCI-GO has already returned. The default implementation does nothing."))

(defgeneric uci-ready (engine)
  (:documentation "Called just before 'readyok' is sent in response to an 'isready' command.
Engines can use this hook to perform any deferred initialization that should be complete before
the GUI considers the engine ready. The default implementation does nothing."))

(defgeneric uci-quit (engine)
  (:documentation "Called when the GUI sends 'quit', instructing the engine to exit as soon as
possible. UCI-RUN will stop reading input after this returns. Subclasses should release
resources and terminate any background threads here. The default implementation does nothing."))

(defmethod uci-engine-name ((engine uci-engine))
  "Monsoon")

(defmethod uci-engine-author ((engine uci-engine))
  "Unknown")

(defmethod uci-engine-options ((engine uci-engine))
  nil)

(defmethod uci-new-game ((engine uci-engine))
  nil)

(defmethod uci-set-option ((engine uci-engine) name value)
  (setf (gethash (string-downcase name) (uci-engine-option-values engine)) value)
  value)

(defmethod uci-position-updated ((engine uci-engine) position)
  (declare (ignore position))
  nil)

(defmethod uci-go ((engine uci-engine) parameters)
  (declare (ignore parameters))
  (error "UCI search not implemented for ~a." (class-of engine)))

(defmethod uci-stop ((engine uci-engine))
  nil)

(defmethod uci-ponderhit ((engine uci-engine))
  nil)

(defmethod uci-ready ((engine uci-engine))
  nil)

(defmethod uci-quit ((engine uci-engine))
  nil)

(defun uci-option-type-string (type)
  (ecase type
    (:check "check")
    (:spin "spin")
    (:combo "combo")
    (:button "button")
    (:string "string")))

(defun uci-option-line (option)
  (format nil "option name ~a type ~a~@[ default ~a~]~@[ min ~a~]~@[ max ~a~]~@[~{ var ~a~}~]"
          (uci-option-name option)
          (uci-option-type-string (uci-option-type option))
          (uci-option-default option)
          (uci-option-min option)
          (uci-option-max option)
          (uci-option-vars option)))

(defun uci-square-string (square)
  (declare (type square square))
  (let ((file (file-of square))
        (rank (rank-of square)))
    (format nil "~c~c"
            (code-char (+ (char-code #\a) file))
            (code-char (+ (char-code #\1) rank)))))

(defun uci-promotion-char (promotion)
  (ecase promotion
    (:queen #\q)
    (:rook #\r)
    (:bishop #\b)
    (:knight #\n)))

(defun uci-move-string (move)
  (cond
    ((null move) "0000")
    ((stringp move) move)
    ((typep move 'move)
     (with-move (from to promotion flags) move
       (declare (ignore flags))
       (format nil "~a~a~@[~c~]"
               (uci-square-string from)
               (uci-square-string to)
               (when promotion (uci-promotion-char promotion)))))
    (t
     (error "Unsupported move type: ~a" move))))

(defun uci-parse-square (square-str)
  (unless (= (length square-str) 2)
    (error "Invalid square: ~a" square-str))
  (let* ((file-char (char-downcase (char square-str 0)))
         (rank-char (char square-str 1))
         (file (- (char-code file-char) (char-code #\a)))
         (rank-digit (digit-char-p rank-char))
         (rank (when rank-digit (1- rank-digit))))
    (unless (<= 0 file 7)
      (error "Invalid square: ~a (file must be a-h)." square-str))
    (unless (and rank (<= 0 rank 7))
      (error "Invalid square: ~a (rank must be 1-8)." square-str))
    (+ (* rank 8) file)))

(defun uci-promotion-piece (char)
  (ecase (char-downcase char)
    (#\q :queen)
    (#\r :rook)
    (#\b :bishop)
    (#\n :knight)))

(defun uci-lookup-move (position from to promotion)
  (it:iter
    (it:for move in (generate-moves position))
    (when (and (eql from (move-from move))
               (eql to (move-to move))
               (eql promotion (move-promotion move))
               (legal-move-p position move))
      (it:leave move))
    (it:finally
     (error "Illegal or unknown move: ~a~a~@[~c~]"
            (uci-square-string from)
            (uci-square-string to)
            (when promotion (uci-promotion-char promotion))))))

(defun uci-parse-move (position move-str)
  (unless (and (stringp move-str)
               (<= 4 (length move-str) 5))
    (error "Invalid move: ~a" move-str))
  (let* ((from (uci-parse-square (subseq move-str 0 2)))
         (to (uci-parse-square (subseq move-str 2 4)))
         (promotion (when (= (length move-str) 5)
                      (uci-promotion-piece (char move-str 4)))))
    (uci-lookup-move position from to promotion)))

(defun uci-join-tokens (tokens)
  (format nil "~{~a~^ ~}" tokens))

(defun uci-parse-integer (token name)
  (unless token
    (error "Missing value for ~a." name))
  (let ((value (handler-case
                   (parse-integer token :junk-allowed nil)
                 (error ()
                   (error "Invalid integer for ~a: ~a." name token)))))
    (when (minusp value)
      (error "Value for ~a must be non-negative: ~a." name token))
    value))

(defun uci-parse-setoption (engine tokens)
  (let ((cursor (rest tokens)))
    (unless (and cursor (string= (string-downcase (first cursor)) "name"))
      (error "Invalid setoption command."))
    (setf cursor (rest cursor))
    (let ((name-tokens '())
          (value-tokens '()))
      (loop while cursor
            for token = (first cursor)
            do (if (string= (string-downcase token) "value")
                   (progn
                     (setf cursor (rest cursor))
                     (setf value-tokens cursor)
                     (setf cursor nil))
                   (progn
                     (push token name-tokens)
                     (setf cursor (rest cursor)))))
      (let ((name (uci-join-tokens (nreverse name-tokens)))
            (value (when value-tokens (uci-join-tokens value-tokens))))
        (unless (plusp (length name))
          (error "setoption requires a name."))
        (uci-set-option engine name value)))))

(defun uci-parse-position (engine tokens)
  (let ((cursor (rest tokens)))
    (unless cursor
      (error "position requires arguments."))
    (let ((pos nil))
      (cond
        ((string= (string-downcase (first cursor)) "startpos")
         (setf pos (position-from-fen +uci-startpos-fen+))
         (setf cursor (rest cursor)))
        ((string= (string-downcase (first cursor)) "fen")
         (setf cursor (rest cursor))
         (when (< (length cursor) 6)
           (error "position fen requires a complete FEN string with six fields."))
         (let* ((fen-fields (subseq cursor 0 6))
                (rest (nthcdr 6 cursor)))
           (when (and rest
                      (not (string= (string-downcase (first rest)) "moves")))
             (error "Unexpected token after FEN: ~a." (first rest)))
           (setf pos (position-from-fen (uci-join-tokens fen-fields)))
           (setf cursor rest)))
        (t
         (error "Unknown position specifier: ~a" (first cursor))))
      (when cursor
        (unless (string= (string-downcase (first cursor)) "moves")
          (error "Unexpected token in position command: ~a" (first cursor)))
        (setf cursor (rest cursor))
        (dolist (move-str cursor)
          (setf pos (do-move pos (uci-parse-move pos move-str)))))
      (setf (uci-engine-position engine) pos)
      (uci-position-updated engine pos)
      pos)))

(defun uci-parse-go (engine tokens)
  (let* ((params (make-uci-go-parameters))
         (cursor (rest tokens))
         (keywords '("searchmoves" "ponder" "wtime" "btime" "winc" "binc"
                     "movestogo" "depth" "nodes" "mate" "movetime" "infinite")))
    (loop while cursor do
      (let ((token (string-downcase (first cursor))))
        (cond
          ((string= token "searchmoves")
           (setf cursor (rest cursor))
           (let ((moves '()))
             (loop while (and cursor
                              (not (member (string-downcase (first cursor))
                                           keywords
                                           :test #'string=)))
                   do (push (uci-parse-move (uci-engine-position engine)
                                            (first cursor))
                            moves)
                      (setf cursor (rest cursor)))
             (setf (uci-go-param-searchmoves params) (nreverse moves))))
          ((string= token "ponder")
           (setf (uci-go-param-ponder params) t)
           (setf cursor (rest cursor)))
          ((string= token "wtime")
           (setf (uci-go-param-wtime params)
                 (uci-parse-integer (second cursor) "wtime"))
           (setf cursor (cddr cursor)))
          ((string= token "btime")
           (setf (uci-go-param-btime params)
                 (uci-parse-integer (second cursor) "btime"))
           (setf cursor (cddr cursor)))
          ((string= token "winc")
           (setf (uci-go-param-winc params)
                 (uci-parse-integer (second cursor) "winc"))
           (setf cursor (cddr cursor)))
          ((string= token "binc")
           (setf (uci-go-param-binc params)
                 (uci-parse-integer (second cursor) "binc"))
           (setf cursor (cddr cursor)))
          ((string= token "movestogo")
           (setf (uci-go-param-movestogo params)
                 (uci-parse-integer (second cursor) "movestogo"))
           (setf cursor (cddr cursor)))
          ((string= token "depth")
           (setf (uci-go-param-depth params)
                 (uci-parse-integer (second cursor) "depth"))
           (setf cursor (cddr cursor)))
          ((string= token "nodes")
           (setf (uci-go-param-nodes params)
                 (uci-parse-integer (second cursor) "nodes"))
           (setf cursor (cddr cursor)))
          ((string= token "mate")
           (setf (uci-go-param-mate params)
                 (uci-parse-integer (second cursor) "mate"))
           (setf cursor (cddr cursor)))
          ((string= token "movetime")
           (setf (uci-go-param-movetime params)
                 (uci-parse-integer (second cursor) "movetime"))
           (setf cursor (cddr cursor)))
          ((string= token "infinite")
           (setf (uci-go-param-infinite params) t)
           (setf cursor (rest cursor)))
          (t
           (error "Unknown go parameter: ~a" token)))))
    params))

(defun uci-write-line (stream line)
  (format stream "~a~%" line)
  (finish-output stream))

(defun uci-send-id (engine stream)
  (uci-write-line stream
                  (format nil "id name ~a" (uci-engine-name engine)))
  (uci-write-line stream
                  (format nil "id author ~a" (uci-engine-author engine)))
  (dolist (option (uci-engine-options engine))
    (uci-write-line stream (uci-option-line option))))

(defun uci-send-bestmove (stream bestmove &optional ponder)
  (let ((bestmove-string (uci-move-string bestmove)))
    (if ponder
        (uci-write-line stream
                        (format nil "bestmove ~a ponder ~a"
                                bestmove-string
                                (uci-move-string ponder)))
        (uci-write-line stream
                        (format nil "bestmove ~a" bestmove-string)))))

(defun uci-handle-line (engine line &key (output *standard-output*))
  (let ((tokens (serapeum:tokens line)))
    (when tokens
      (let ((command (string-downcase (first tokens))))
        (cond
          ((string= command "uci")
           (uci-send-id engine output)
           (uci-write-line output "uciok"))
          ((string= command "isready")
           (uci-ready engine)
           (uci-write-line output "readyok"))
          ((string= command "ucinewgame")
           (uci-new-game engine))
          ((string= command "setoption")
           (uci-parse-setoption engine tokens))
          ((string= command "position")
           (uci-parse-position engine tokens))
          ((string= command "go")
           (let ((params (uci-parse-go engine tokens)))
             (multiple-value-bind (bestmove ponder)
                 (uci-go engine params)
               (uci-send-bestmove output bestmove ponder))))
          ((string= command "stop")
           (uci-stop engine))
          ((string= command "ponderhit")
           (uci-ponderhit engine))
          ((string= command "debug")
           (when (second tokens)
             (setf (uci-engine-debug engine)
                   (string= (string-downcase (second tokens)) "on"))))
          ((string= command "quit")
           (uci-quit engine)
           :quit)
          (t
           nil))))))

(defun uci-run (engine &key (input *standard-input*) (output *standard-output*))
  (loop for line = (read-line input nil nil)
        while line
        do (handler-case
               (when (eq (uci-handle-line engine line :output output) :quit)
                 (return :quit))
             (error (condition)
               (uci-write-line output
                               (format nil "info string UCI error: ~a"
                                       condition))))))
