;;;; t/dispatch-test.lisp
(in-package #:cl-host-kit/test)

(defpackage #:host-kit/dispatch-test-target
  (:use #:cl)
  (:export #:%add-one))
(in-package #:host-kit/dispatch-test-target)
(defun %add-one (x) (1+ x))
(in-package #:cl-host-kit/test)

(describe
  "symbol-call"
  (it
    "calls the named function in the named package with the given arguments"
    (expect (host-kit:symbol-call :host-kit/dispatch-test-target :%add-one 1)
            :to-equal
            2))
  (it
    "accepts string designators for package and name"
    (expect (host-kit:symbol-call "HOST-KIT/DISPATCH-TEST-TARGET" "%ADD-ONE" 41)
            :to-equal
            42))
  (it
    "signals a package-error when the package does not exist"
    (signals package-error (host-kit:symbol-call :host-kit/no-such-package :whatever)))
  (it
    "signals an error when the symbol does not name a function"
    (signals error
      (host-kit:symbol-call :host-kit/dispatch-test-target :no-such-function))))
