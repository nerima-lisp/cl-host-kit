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

(describe "with-environment-variables"
  (it "scopes multiple variables and restores their original values"
    (let ((present "CL_HOST_KIT_SCOPED_PRESENT")
          (missing "CL_HOST_KIT_SCOPED_MISSING"))
      (unwind-protect
           (progn
             (setf (getenv present) "original")
             (setf (getenv missing) nil)
             (with-environment-variables ((present "replacement")
                                          (missing "created"))
               (expect (getenv present) :to-equal "replacement")
               (expect (getenv missing) :to-equal "created"))
             (expect (getenv present) :to-equal "original")
             (expect (getenv missing) :to-be nil))
        (setf (getenv present) nil)
        (setf (getenv missing) nil))))

  (it "restores variables when the body signals an error"
    (let ((name "CL_HOST_KIT_SCOPED_ERROR"))
      (unwind-protect
           (progn
             (setf (getenv name) "original")
             (signals error
               (with-environment-variables ((name "replacement"))
                 (error "scope failure")))
             (expect (getenv name) :to-equal "original"))
        (setf (getenv name) nil))))

  (it "evaluates bindings once and can temporarily unset a variable"
    (let ((name "CL_HOST_KIT_SCOPED_UNSET")
          (name-evaluations 0)
          (value-evaluations 0))
      (unwind-protect
           (progn
             (setf (getenv name) "original")
             (with-environment-variables
                 (((progn (incf name-evaluations) name)
                   (progn (incf value-evaluations) nil)))
               (expect (getenv name) :to-be nil))
             (expect name-evaluations :to-equal 1)
             (expect value-evaluations :to-equal 1)
             (expect (getenv name) :to-equal "original"))
        (setf (getenv name) nil)))))

(describe "call-with-environment-variables"
  (it "restores variables when its thunk signals an error"
    (let ((name "CL_HOST_KIT_CPS_ENVIRONMENT"))
      (unwind-protect
           (progn
             (setf (getenv name) "original")
             (signals error
               (call-with-environment-variables
                (list (list name "replacement"))
                (lambda ()
                  (expect (getenv name) :to-equal "replacement")
                  (error "scope failure"))))
             (expect (getenv name) :to-equal "original"))
        (setf (getenv name) nil))))

  (it "validates every binding before changing the environment"
    (let ((name "CL_HOST_KIT_INVALID_ENVIRONMENT"))
      (unwind-protect
           (progn
             (setf (getenv name) "original")
             (signals error
               (call-with-environment-variables
                (list (list name "replacement")
                      (list 42 "invalid"))
                (lambda () (error "must not run"))))
             (expect (getenv name) :to-equal "original"))
        (setf (getenv name) nil)))))
