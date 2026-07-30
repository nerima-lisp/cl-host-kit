;;;; src/conditions.lisp
;;;;
;;;; HOST-KIT-ERROR is the package-wide base condition (CODING_STANDARD.md's
;;;; "package-specific base condition type" rule), so a caller can catch every
;;;; failure this library signals with one HANDLER-CASE clause. Concrete
;;;; subtypes distinguish OS failures, unsupported implementations, and program
;;;; failures caused by a timeout or an unexpected terminal status.
(in-package #:host-kit)

(define-condition host-kit-error (error)
  ()
  (:documentation "Base condition for every error HOST-KIT signals."))

(define-condition host-operation-failed (host-kit-error)
  ((operation :initarg :operation
              :reader host-operation-failed-operation
              :documentation "Keyword naming the attempted operation, e.g. :CHDIR.")
   (target :initarg :target
           :reader host-operation-failed-target
           :documentation "The pathname or string the operation was attempted on, or NIL.")
   (reason :initarg :reason
           :reader host-operation-failed-reason
           :documentation "The underlying condition that caused the failure."))
  (:report
   (lambda (condition stream)
     (format stream "HOST-KIT operation ~S failed~@[ on ~S~]: ~A"
             (host-operation-failed-operation condition)
             (host-operation-failed-target condition)
             (host-operation-failed-reason condition))))
  (:documentation "Signalled when an underlying OS call (sb-posix, sb-ext, or
plain Lisp file I/O) fails while HOST-KIT is performing OPERATION on TARGET."))

(define-condition unsupported-implementation (host-kit-error)
  ((feature :initarg :feature
            :reader unsupported-implementation-feature
            :documentation "Keyword naming the HOST-KIT operation that was called."))
  (:report
   (lambda (condition stream)
     (format stream "HOST-KIT:~A is not supported on this Lisp implementation (SBCL only)."
             (unsupported-implementation-feature condition))))
  (:documentation "Signalled when a HOST-KIT operation is invoked on a
non-SBCL implementation. HOST-KIT targets SBCL only; every public function
still has a #-sbcl definition so loading the system elsewhere fails with this
clear condition instead of an undefined-function error at the call site."))

(define-condition process-timeout (host-kit-error)
  ((program :initarg :program :reader process-timeout-program)
   (arguments :initarg :arguments :reader process-timeout-arguments)
   (seconds :initarg :seconds :reader process-timeout-seconds)
   (result :initarg :result :reader process-timeout-result))
  (:report
   (lambda (condition stream)
     (format stream "HOST-KIT program ~S timed out after ~,3F seconds."
             (process-timeout-program condition)
             (process-timeout-seconds condition))))
  (:documentation "Signalled when RUN-PROGRAM reaches its timeout after
terminating and reaping the child process group. RESULT holds captured output
  and the terminal status."))

(define-condition file-lock-timeout (host-kit-error)
  ((seconds :initarg :seconds :reader file-lock-timeout-seconds))
  (:report
   (lambda (condition stream)
     (format stream "HOST-KIT advisory file lock timed out after ~,3F seconds."
             (file-lock-timeout-seconds condition))))
  (:documentation "Signalled when CALL-WITH-ADVISORY-FILE-LOCK cannot acquire
a conflicting cooperative lock before its requested timeout."))

(define-condition process-exit-error (host-kit-error)
  ((program :initarg :program :reader process-exit-error-program)
   (arguments :initarg :arguments :reader process-exit-error-arguments)
   (exit-code :initarg :exit-code :reader process-exit-error-exit-code)
   (signal :initarg :signal :reader process-exit-error-signal)
   (expected-exit-codes :initarg :expected-exit-codes
                        :reader process-exit-error-expected-exit-codes)
   (result :initarg :result :reader process-exit-error-result))
  (:report
   (lambda (condition stream)
     (format stream "HOST-KIT program ~S exited with ~:[code ~S~;signal ~S~]; expected one of ~S."
             (process-exit-error-program condition)
             (process-exit-error-signal condition)
             (or (process-exit-error-signal condition)
                 (process-exit-error-exit-code condition))
             (process-exit-error-expected-exit-codes condition))))
  (:documentation "Signalled by ENSURE-PROGRAM-SUCCESS when a completed
PROCESS-RESULT does not have an expected exit code. RESULT retains all captured
terminal data without placing command output in the condition report."))

(defun %signal-host-operation-failed (operation target reason)
  (error 'host-operation-failed :operation operation :target target :reason reason))

(defun %unsupported (feature)
  (error 'unsupported-implementation :feature feature))

(defmacro %with-host-operation ((operation target) &body body)
  "Run BODY, converting any non-HOST-KIT-ERROR condition it signals into a
HOST-OPERATION-FAILED naming OPERATION and TARGET. A condition that is already
a HOST-KIT-ERROR (including one raised by a nested %WITH-HOST-OPERATION) is
re-signalled unchanged so wrapping stays single-layered."
  `(handler-case (progn ,@body)
     (host-kit-error (condition) (error condition))
     (error (condition) (%signal-host-operation-failed ,operation ,target condition))))
