;;;; t/environment-test.lisp
;;;
;;; QUIT wraps SB-EXT:EXIT, which terminates the running process. There is no
;;; in-process way to call it and observe a return value -- doing so would
;;; kill the test runner itself -- so it is exercised only by manual and
;;; integration testing, not this unit suite.
(in-package #:cl-host-kit/test)

(describe "getenv"
  (it "returns NIL for an unset variable"
    (expect (getenv "CL_HOST_KIT_TEST_DEFINITELY_UNSET") :to-be nil))

  (it "returns the value SETF wrote"
    (unwind-protect
         (progn
           (setf (getenv "CL_HOST_KIT_TEST_VAR") "42")
           (expect (getenv "CL_HOST_KIT_TEST_VAR") :to-equal "42"))
      (setf (getenv "CL_HOST_KIT_TEST_VAR") nil)))

  (it "SETF to NIL unsets the variable"
    (setf (getenv "CL_HOST_KIT_TEST_VAR2") "x")
    (setf (getenv "CL_HOST_KIT_TEST_VAR2") nil)
    (expect (getenv "CL_HOST_KIT_TEST_VAR2") :to-be nil)))
