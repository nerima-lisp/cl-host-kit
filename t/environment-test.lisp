;;;; t/environment-test.lisp
;;;
;;; QUIT wraps SB-EXT:EXIT, so its behavior is verified in a separate SBCL
;;; process rather than terminating the test runner.
(in-package #:cl-host-kit/test)

(defmacro %with-restored-environment ((&rest names) &body body)
  `(let ((saved-values
        (list
          ,@(mapcar
            (lambda (name)
              `(cons ,name (getenv ,name)))
            names))))
    (unwind-protect (progn
        ,@body)
      (dolist (entry saved-values)
        (setf (getenv (car entry)) (cdr entry))))))

(describe
  "getenv"
  (it
    "returns NIL for an unset variable"
    (%with-restored-environment
      ("CL_HOST_KIT_TEST_DEFINITELY_UNSET")
      (setf (getenv "CL_HOST_KIT_TEST_DEFINITELY_UNSET") nil)
      (expect (getenv "CL_HOST_KIT_TEST_DEFINITELY_UNSET") :to-be nil)))
  (it
    "returns the value SETF wrote"
    (%with-restored-environment
      ("CL_HOST_KIT_TEST_VAR")
      (setf (getenv "CL_HOST_KIT_TEST_VAR") "42")
      (expect (getenv "CL_HOST_KIT_TEST_VAR") :to-equal "42")))
  (it
    "SETF to NIL unsets the variable"
    (%with-restored-environment
      ("CL_HOST_KIT_TEST_VAR2")
      (setf (getenv "CL_HOST_KIT_TEST_VAR2") "x")
      (setf (getenv "CL_HOST_KIT_TEST_VAR2") nil)
      (expect (getenv "CL_HOST_KIT_TEST_VAR2") :to-be nil)))
  (it
    "restores nested bindings"
    (let ((name "CL_HOST_KIT_TEST_NESTED")
          (original (getenv "CL_HOST_KIT_TEST_NESTED")))
      (%with-restored-environment
        (name)
        (setf (getenv name) "outer")
        (%with-restored-environment
          (name)
          (setf (getenv name) "inner")
          (expect (getenv name) :to-equal "inner"))
        (expect (getenv name) :to-equal "outer"))
      (expect (getenv name) :to-equal original)))
  (it
    "restores a value after an error"
    (let ((name "CL_HOST_KIT_TEST_ERROR")
          (original (getenv "CL_HOST_KIT_TEST_ERROR")))
      (handler-case (%with-restored-environment
          (name)
          (setf (getenv name) "temporary")
          (error "expected test error"))
        (error ()
          nil))
      (expect (getenv name) :to-equal original))))

(progn
  (describe
    "getenv failure handling"
    (it
      "wraps invalid environment names in HOST-OPERATION-FAILED"
      (let ((condition
            (handler-case (setf (getenv "CL_HOST_KIT_TEST=INVALID") "value")
              (host-operation-failed (condition)
                condition))))
        (expect condition :to-be-truthy)
        (expect (host-operation-failed-operation condition) :to-equal :setf-getenv)
        (expect
          (host-operation-failed-target condition)
          :to-equal
          "CL_HOST_KIT_TEST=INVALID")
        (expect (host-operation-failed-reason condition) :to-be-truthy))))
  (describe
    "quit"
    (it
      "terminates a child SBCL with the supplied code"
      (let* ((source-directory (asdf:system-source-directory "cl-host-kit"))
             (source-files
            (mapcar
              (lambda (file)
                (namestring (merge-pathnames file source-directory)))
              '("src/package.lisp" "src/conditions.lisp" "src/environment.lisp")))
             (form
            (format
              nil
              "(progn ~{(load ~S)~} (funcall (find-symbol \"QUIT\" \"HOST-KIT\") 23))"
              source-files))
             (process
            (sb-ext:run-program
              (namestring sb-ext:*runtime-pathname*)
              (list "--noinform" "--non-interactive" "--eval" form)
              :search
              nil
              :wait
              t
              :output
              nil
              :error
              nil)))
        (expect (sb-ext:process-exit-code process) :to-equal 23)))))
