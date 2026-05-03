(defpackage monsoon/tests/main
  (:use :cl
        :monsoon
        :rove))
(in-package :monsoon/tests/main)

;; NOTE: To run this test file, execute `(asdf:test-system :monsoon)' in your Lisp.

(deftest test-target-1
  (testing "should (= 1 1) to be true"
    (ok (= 1 1))))
