;;;; t/package.lisp
;;;
;;; Imports the cl-weave DSL explicitly (no blanket :USE), so a future
;;; cl-weave export never silently shadows a host-kit symbol. CL:DESCRIBE is
;;; shadowed in favor of CL-WEAVE:DESCRIBE, per the cl-weave installation
;;; contract (see e.g. cl-json-kit/t/package.lisp, cl-log-kit/t/package.lisp).
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
