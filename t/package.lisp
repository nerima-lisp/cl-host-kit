;;;; t/package.lisp
;;;
;;; Import the cl-weave DSL explicitly and shadow CL:DESCRIBE as required by
;;; the test framework.
(defpackage #:cl-host-kit/test
  (:use #:cl #:host-kit)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
   #:it
   #:it-each
   #:it-property
   #:gen-character
   #:gen-string
   #:expect
   #:signals
   #:run-all)
  (:export #:run-tests))

(in-package #:cl-host-kit/test)

(defun run-tests ()
  "Run every registered spec, signalling on any failure so ASDF's TEST-OP fails."
  (unless (run-all :reporter :spec :timeout-ms 10000)
    (error "cl-host-kit test suite failed"))
  (format t "~&cl-host-kit/test: successful completion with 0 failures~%")
  t)
