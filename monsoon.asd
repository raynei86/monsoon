(defsystem "monsoon"
  :version "0.0.1"
  :author "Lihui Zhang"
  :license "MIT"
  :depends-on ("iterate" "serapeum")
  :components ((:module "src"
                :components
                ((:file "main"))))
  :description ""
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
