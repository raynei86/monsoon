;;;; Move generation, legality classification, and perft.

(in-package #:monsoon)

(declaim (optimize (speed 3) (safety 1)))

(defun emit-moves (from targets-bb &optional (flags 0))
  "Return moves from FROM to each target in TARGETS-BB."
  (declare (type square from)
           (type bitboard targets-bb))
  (let ((moves '()))
    (do-bitboard (target targets-bb)
      (push (make-move from target nil flags) moves))
    (nreverse moves)))

(defmacro generate-major-piece-moves (pieces-bb attack-expr friendly enemy)
  "Generate pseudo-legal moves for pieces that are not pawns in pieces-bb.
   ATTACK-EXPR is spliced with FROM bound to each piece square; pass e.g.
   (rook-attack-mask from occupied)."
  `(let ((moves '()))
     (do-bitboard (from ,pieces-bb)
       (let* ((attacks (logandc2 ,attack-expr ,friendly))
              (captures (logand attacks ,enemy))
              (quiets (logandc2 attacks ,enemy)))
         (setf moves (nconc moves
                            (emit-moves from captures +move-flag-capture+)
                            (emit-moves from quiets)))))
     moves))

(defun generate-knight-moves (position)
  "Generate pseudo-legal knight moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :knight side))
     (aref +knight-attacks+ from)
     friendly enemy)))

(defun generate-king-moves (position)
  "Generate pseudo-legal king moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :king side))
     (aref +king-attacks+ from)
     friendly enemy)))

(defun generate-rook-moves (position)
  "Generate pseudo-legal rook moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :rook side))
     (rook-attack-mask from occupied)
     friendly enemy)))

(defun generate-bishop-moves (position)
  "Generate pseudo-legal bishop moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :bishop side))
     (bishop-attack-mask from occupied)
     friendly enemy)))

(defun generate-queen-moves (position)
  "Generate pseudo-legal queen moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (generate-major-piece-moves
     (aref (pos-boards position) (colored-piece-index :queen side))
     (queen-attack-mask from occupied)
     friendly enemy)))

;; Pawn move generation

(defmacro emit-pawn-moves (targets shift &optional (flags 0))
  "Emit moves for all targets, deriving the source square as (target - shift)."
  `(let ((moves '()))
     (do-bitboard (target ,targets)
       (push (make-move (- target ,shift) target nil ,flags) moves))
     (nreverse moves)))

(defmacro emit-pawn-promos (targets shift &optional (flags 0))
  "Emit all 4 promotion types as moves"
  `(let ((moves '()))
     (do-bitboard (target ,targets)
       (dolist (promo '(:queen :rook :bishop :knight))
         (push (make-move (- target ,shift) target promo ,flags) moves)))
     (nreverse moves)))

(declaim (inline shift-board))

(defun shift-board (bb shift)
  "Shift BB by SHIFT squares, discarding bits pushed off the board."
  (declare (type bitboard bb) (type fixnum shift))
  (logand (ash bb shift) +full-board+))

(defun generate-pawn-moves (position)
  "Generate pseudo-legal pawn moves for the side to move."
  ;; Pawn moves use shifted masks for pushes and captures.
  ;; push1/push2 are quiet advances; cap-e/cap-w are capture masks.
  (with-position (side occupied friendly enemy) position
    (let* ((params (side-params side))
           (push-shift (side-push-shift params))
           (cap-e-shift (side-cap-e-shift params))
           (cap-w-shift (side-cap-w-shift params))
           (start-rank (side-start-rank params))
           (promo-rank (side-promo-rank params))
           (pawns (aref (pos-boards position) (colored-piece-index :pawn side)))
           (empty (logand (lognot occupied) +full-board+))

           ;; Pushes
           (push1 (logand (shift-board pawns push-shift) empty))
           (push2 (logand (shift-board (logand (shift-board (logand pawns start-rank)
                                                            push-shift)
                                               empty)
                                       push-shift)
                          empty))

           ;; Captures
           (cap-e (logand (ash (logand pawns +not-file-h+) cap-e-shift) enemy))
           (cap-w (logand (ash (logand pawns +not-file-a+) cap-w-shift) enemy))

           ;; Split promotions from regular moves
           (push1-promo (logand    push1 promo-rank))
           (push1-quiet (logandc2  push1 promo-rank))
           (cap-e-promo (logand    cap-e promo-rank))
           (cap-e-quiet (logandc2  cap-e promo-rank))
           (cap-w-promo (logand    cap-w promo-rank))
           (cap-w-quiet (logandc2  cap-w promo-rank)))

      (nconc
       (emit-pawn-moves push1-quiet push-shift)
       (emit-pawn-moves push2 (* 2 push-shift) +move-flag-double+)
       (emit-pawn-moves cap-e-quiet cap-e-shift +move-flag-capture+)
       (emit-pawn-moves cap-w-quiet cap-w-shift +move-flag-capture+)

       (emit-pawn-promos push1-promo push-shift)
       (emit-pawn-promos cap-e-promo cap-e-shift +move-flag-capture+)
       (emit-pawn-promos cap-w-promo cap-w-shift +move-flag-capture+)

       ;; En passant uses capture logic against the ep square.
       (when (pos-ep-square position)
         (let* ((ep-bb    (ash 1 (pos-ep-square position)))
                (ep-cap-e (logand (ash (logand pawns +not-file-h+) cap-e-shift) ep-bb))
                (ep-cap-w (logand (ash (logand pawns +not-file-a+) cap-w-shift) ep-bb))
                (ep-flags (logior +move-flag-capture+ +move-flag-ep+)))
           (nconc
            (emit-pawn-moves ep-cap-e cap-e-shift ep-flags)
            (emit-pawn-moves ep-cap-w cap-w-shift ep-flags))))))))

(defun generate-castling-moves (position)
  "Generate pseudo-legal castling moves for the side to move."
  (with-position (side occupied friendly enemy) position
    (let ((params (side-params side))
          (rights (pos-castling position))
          (moves '()))
      (when (and (logtest rights (side-kingside-right params))
                 (not (logtest occupied (side-kingside-empty params))))
        (push (make-move (side-king-sq params) (side-kingside-sq params)
                         nil +move-flag-kingside+)
              moves))
      (when (and (logtest rights (side-queenside-right params))
                 (not (logtest occupied (side-queenside-empty params))))
        (push (make-move (side-king-sq params) (side-queenside-sq params)
                         nil +move-flag-queenside+)
              moves))
      moves)))

;; Final stages, move legality and actually making the moves

(defun generate-moves (position)
  "Generate all pseudo-legal moves for the side to move."
  (nconc (generate-pawn-moves   position)
          (generate-knight-moves position)
          (generate-bishop-moves position)
          (generate-rook-moves   position)
          (generate-queen-moves  position)
          (generate-king-moves   position)
          (generate-castling-moves position)))

(defun checkers (pos color)
  "Return a bitboard of the squares of enemy pieces giving check to COLOR's king."
  (declare (type position pos) (type color color))
  (let* ((king-bb  (aref (pos-boards pos) (colored-piece-index :king color)))
         (king-sq  (lsb king-bb))
         (opp      (opponent color))
         (occupied (pos-occupied-squares pos))
         (opp-pawns   (aref (pos-boards pos) (colored-piece-index :pawn   opp)))
         (opp-knights (aref (pos-boards pos) (colored-piece-index :knight opp)))
         (opp-bishops (aref (pos-boards pos) (colored-piece-index :bishop opp)))
         (opp-rooks   (aref (pos-boards pos) (colored-piece-index :rook   opp)))
         (opp-queens  (aref (pos-boards pos) (colored-piece-index :queen  opp)))
         (opp-king    (aref (pos-boards pos) (colored-piece-index :king   opp)))
         ;; King-shift trick: an enemy pawn attacks the king from exactly the
         ;; squares the defender's own pawns would capture, so shift the king
         ;; by the defender's capture shifts.
         (params (side-params color))
         (pawn-cap-e (side-cap-e-shift params))
         (pawn-cap-w (side-cap-w-shift params)))
    (logior
     (logand (ash (logand king-bb +not-file-h+) pawn-cap-e) opp-pawns)
     (logand (ash (logand king-bb +not-file-a+) pawn-cap-w) opp-pawns)
     (logand (aref +knight-attacks+ king-sq) opp-knights)
     (logand (bishop-attack-mask king-sq occupied)
             (logior opp-bishops opp-queens))
     (logand (rook-attack-mask king-sq occupied)
             (logior opp-rooks opp-queens))
     (logand (aref +king-attacks+ king-sq) opp-king))))

(defun king-in-check-p (pos color)
  "Return true if COLOR's king is in check in POS."
  (not (zerop (checkers pos color))))

(defstruct (legality-context (:constructor %make-legality-context)
                             (:conc-name legality-context-))
  "Precomputed invariants used to classify move legality without making the
   move or scanning for checks on every candidate."
  (side nil :type color)
  (king-sq 0 :type square)
  (in-check-p nil)
  (king-danger 0 :type bitboard)
  (pinned 0 :type bitboard)
  (pin-lines nil :type (or null (simple-array bitboard (64))))
  (evasion-mask 0 :type bitboard))

(defun evasion-mask (pos side)
  "Return the target squares a non-king move must reach to resolve a check on
   SIDE. Returns +FULL-BOARD+ when SIDE is not in check and 0 for double check."
  (let* ((checkers-bb (checkers pos side))
         (n (logcount checkers-bb)))
    (cond
      ((zerop n) +full-board+)
      ((> n 1) 0)
      (t (let* ((king-sq    (lsb (aref (pos-boards pos) (colored-piece-index :king side))))
                (checker-sq (lsb checkers-bb)))
           (logior (ash 1 checker-sq)
                   (aref +between+ king-sq checker-sq)))))))

(defun evasion-move-p (ctx move)
  "Return true if MOVE resolves the check recorded in context CTX.
   Only called for non-king moves while the side to move is in check."
  (with-move (from to promotion flags) move
    (declare (ignore promotion flags))
    (and (logtest (ash 1 to) (legality-context-evasion-mask ctx))
         (or (not (logbitp from (legality-context-pinned ctx)))
             (logtest (ash 1 to) (aref (legality-context-pin-lines ctx) from))))))

(defun make-legality-context (pos)
  "Build the legality invariants for POS's side to move."
  (let* ((side (pos-side-to-move pos))
         (king-bb (aref (pos-boards pos) (colored-piece-index :king side)))
         (king-sq (lsb king-bb))
         (king-danger (attacked-by-kingless pos side))
         (in-check-p (logbitp king-sq king-danger)))
    (multiple-value-bind (pinned pin-lines)
        (pinned-pieces pos side)
      (%make-legality-context
       :side side
       :king-sq king-sq
       :in-check-p in-check-p
       :king-danger king-danger
       :pinned pinned
       :pin-lines pin-lines
       :evasion-mask (if in-check-p (evasion-mask pos side) +full-board+)))))

(defun move-legal-p (ctx pos move)
  "Return true if MOVE is legal in POS, using the precomputed context CTX."
  (let ((side (legality-context-side ctx))
        (king-sq (legality-context-king-sq ctx)))
    (with-move (from to promotion flags) move
      (declare (ignore promotion))
      (cond
        ;; Castling: illegal out of, through, or into check.
        ((logtest flags (logior +move-flag-kingside+ +move-flag-queenside+))
         (let ((params (side-params side)))
           (and (not (legality-context-in-check-p ctx))
                (not (logtest (attacked-by pos (opponent side))
                              (if (logtest flags +move-flag-kingside+)
                                  (side-kingside-safe params)
                                  (side-queenside-safe params)))))))
        ;; King moves: destination must not be attacked. Enemy attacks were
        ;; computed with our king removed, so retreats onto a vacated line
        ;; (which the moving king would otherwise block) are caught.
        ((= from king-sq)
         (not (logbitp to (legality-context-king-danger ctx))))
        ;; En passant removes two pawns, which can expose a rank attack.
        ((logtest flags +move-flag-ep+)
         (not (king-in-check-p (do-move pos move) side)))
        ;; In check: only capturing the checker or blocking its line helps.
        ((legality-context-in-check-p ctx)
         (evasion-move-p ctx move))
        ;; Pinned pieces must stay on their pin line.
        ((logbitp from (legality-context-pinned ctx))
         (logtest (ash 1 to) (aref (legality-context-pin-lines ctx) from)))
        ;; Everything else is legal.
        (t t)))))

(defun legal-move-p (pos move)
  "Return true if MOVE is legal in POS."
  (move-legal-p (make-legality-context pos) pos move))

(defun generate-legal-moves (pos)
  "Generate the legal moves for the side to move in POS."
  (let ((ctx (make-legality-context pos)))
    (remove-if-not (lambda (move) (move-legal-p ctx pos move))
                   (generate-moves pos))))

(defun perft (pos depth)
  "Count leaf nodes by enumerating legal moves to DEPTH."
  (declare (type (and fixnum (integer 0 *)) depth)
           (values fixnum))
  (if (zerop depth)
      1
      (let ((ctx (make-legality-context pos))
            (total 0))
        (declare (type fixnum total))
        (dolist (move (generate-moves pos) (the fixnum total))
          (when (move-legal-p ctx pos move)
            (with-move-applied (pos move)
              (incf (the fixnum total)
                    (the fixnum (perft pos (1- depth))))))))))
