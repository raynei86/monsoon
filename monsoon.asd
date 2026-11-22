(defsystem "monsoon"
  :version "0.0.1"
  :author "Lihui Zhang"
  :license "MIT"
  :depends-on ("serapeum")
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "types")
                 (:file "castling" :depends-on ("types"))
                 (:file "position" :depends-on ("types" "castling"))
                 (:file "utils" :depends-on ("types"))
                 (:file "attacks" :depends-on ("types" "position" "utils"))
                 (:file "movegen" :depends-on ("types" "position" "utils" "attacks" "castling"))
                 (:file "fen" :depends-on ("position" "types"))
                 (:file "uci" :depends-on ("fen" "movegen")))))
  :description "A chess library"
  :in-order-to ((test-op (test-op "monsoon/tests"))))

(defsystem "monsoon/tests"
  :author "Lihui Zhang"
  :license ""
  :depends-on ("monsoon"
               "rove")
  :components ((:module "tests"
                :components
                ((:file "main"))))
  :description "Test system for monsoon"
  :perform (test-op (op c) (symbol-call :rove :run c)))
