(defpackage monsoon/tests/main
  (:use :cl
        :monsoon
        :rove))
(in-package :monsoon/tests/main)

;; NOTE: To run this test file, execute `(asdf:test-system :monsoon)' in your Lisp.

(defparameter +start-fen+
  "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

(defparameter +lone-knight-fen+
  "8/8/8/3N4/8/8/8/8 w - - 0 1")

(defparameter +pawn-capture-fen+
  "8/8/8/3p4/4P3/8/8/4K3 w - - 0 1")

(defparameter +check-fen+
  "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1")

(defparameter +promotion-fen+
  "8/4P3/8/8/8/8/8/4K3 w - - 0 1")

(defun find-move (moves from-square to-square &key promotion)
  "Return the first move in MOVES that matches FROM-SQUARE/TO-SQUARE and optional PROMOTION."
  (find-if (lambda (move)
             (with-move (from to move-promotion flags) move
               (declare (ignore flags))
               (and (= from from-square)
                    (= to to-square)
                    (or (null promotion) (eql move-promotion promotion)))))
           moves))

(deftest test-square-and-coordinates
  (testing "sq maps coordinates to indices"
    (ok (= 0 (sq :a1)))
    (ok (= 7 (sq :h1)))
    (ok (= 56 (sq :a8)))
    (ok (= 63 (sq :h8)))
    (ok (= 28 (sq :e4))))
  (testing "file-of and rank-of map indices"
    (ok (= 0 (file-of (sq :a1))))
    (ok (= 0 (rank-of (sq :a1))))
    (ok (= 7 (file-of (sq :h8))))
    (ok (= 7 (rank-of (sq :h8))))))

(deftest test-colored-piece-index
  (testing "colored piece indices are stable"
    (ok (= 0 (colored-piece-index :pawn :white)))
    (ok (= 1 (colored-piece-index :pawn :black)))
    (ok (= 10 (colored-piece-index :king :white)))
    (ok (= 11 (colored-piece-index :king :black)))))

(deftest test-opponent
  (testing "opponent flips colors"
    (ok (eq :black (opponent :white)))
    (ok (eq :white (opponent :black)))))

(deftest test-find-move
  (testing "find-move locates moves by from/to and promotion"
    (let* ((pos (position-from-fen +start-fen+))
           (moves (generate-moves pos))
           (move (find-move moves (sq :g1) (sq :f3))))
      (ok move)
      (with-move (from to promotion flags) move
        (declare (ignore flags))
        (ok (= (sq :g1) from))
        (ok (= (sq :f3) to))
        (ok (null promotion)))
      (ok (not (find-move moves (sq :g1) (sq :g3))))))
  (testing "find-move matches promotion moves"
    (let* ((pos (position-from-fen +promotion-fen+))
           (moves (generate-moves pos))
           (move (find-move moves (sq :e7) (sq :e8) :promotion :queen))
           (default-move (find-move moves (sq :e7) (sq :e8))))
      (ok move)
      (with-move (from to promotion flags) move
        (declare (ignore flags))
        (ok (= (sq :e7) from))
        (ok (= (sq :e8) to))
        (ok (eq :queen promotion)))
      (ok default-move)
      (with-move (from to promotion flags) default-move
        (declare (ignore flags))
        (ok (= (sq :e7) from))
        (ok (= (sq :e8) to))
        (ok (eq :queen promotion))))))

(deftest test-position-from-fen
  (testing "start position parses correctly"
    (let ((pos (position-from-fen +start-fen+)))
      (ok (eq :white (pos-side-to-move pos)))
      (ok (null (pos-ep-square pos)))
      (ok (= 0 (pos-halfmove-clock pos)))
      (ok (= 1 (pos-fullmove-number pos)))
      (ok (occupied-p pos (sq :e1)))
      (ok (eq :king (piece-at pos (sq :e1))))
      (ok (eq :white (color-at pos (sq :e1))))
      (ok (eq :king (piece-at pos (sq :e8))))
      (ok (eq :black (color-at pos (sq :e8))))
      (ok (= #b1111 (pos-castling pos))))))

(deftest test-generate-moves-starting-position
  (testing "starting position has 20 pseudo-legal moves"
    (let* ((pos (position-from-fen +start-fen+))
           (moves (generate-moves pos)))
      (ok (= 20 (length moves)))
      (ok (find-move moves (sq :g1) (sq :f3)))
      (ok (find-move moves (sq :b1) (sq :c3))))))

(deftest test-knight-moves-from-center
  (testing "a lone knight has eight moves from d5"
    (let* ((pos (position-from-fen +lone-knight-fen+))
           (moves (generate-moves pos)))
      (ok (= 8 (length moves)))
      (ok (find-move moves (sq :d5) (sq :f6)))
      (ok (find-move moves (sq :d5) (sq :b4))))))

(deftest test-do-move-double-push
  (testing "double pawn push updates en passant square and side to move"
    (let* ((pos (position-from-fen +start-fen+))
           (move (find-move (generate-moves pos)
                            (sq :e2) (sq :e4))))
      (ok move)
      (let ((new-pos (do-move pos move)))
        (ok (not (occupied-p new-pos (sq :e2))))
        (ok (occupied-p new-pos (sq :e4)))
        (ok (eq :pawn (piece-at new-pos (sq :e4))))
        (ok (eq :white (color-at new-pos (sq :e4))))
        (ok (= (sq :e3) (pos-ep-square new-pos)))
        (ok (eq :black (pos-side-to-move new-pos)))))))

(deftest test-do-move-capture
  (testing "captures remove the victim and place the capturing piece"
    (let* ((pos (position-from-fen +pawn-capture-fen+))
           (move (find-move (generate-moves pos)
                            (sq :e4) (sq :d5))))
      (ok move)
      (let ((new-pos (do-move pos move)))
        (ok (not (occupied-p new-pos (sq :e4))))
        (ok (occupied-p new-pos (sq :d5)))
        (ok (eq :pawn (piece-at new-pos (sq :d5))))
        (ok (eq :white (color-at new-pos (sq :d5))))
        (ok (null (pos-ep-square new-pos)))))))

(deftest test-legal-move-p-in-check
  (testing "moves that keep the king in check are illegal"
    (let* ((pos (position-from-fen +check-fen+))
           (moves (generate-moves pos))
           (illegal (find-move moves (sq :e8) (sq :e7))))
      (ok (king-in-check-p pos :black))
      (ok illegal)
      (ok (not (legal-move-p pos illegal))))))
