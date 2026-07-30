;;;; src/conditions.lisp
;;;;
;;;; HOST-KIT-ERROR is the package-wide base condition (CODING_STANDARD.md's
;;;; "package-specific base condition type" rule), so a caller can catch every
;;;; failure this library signals with one HANDLER-CASE clause. The concrete
;;;; subtype wraps failures from host operations.
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

(defun %signal-host-operation-failed (operation target reason)
  (error 'host-operation-failed :operation operation :target target :reason reason))

(defmacro %with-host-operation ((operation target) &body body)
  "Run BODY, converting any non-HOST-KIT-ERROR condition it signals into a
HOST-OPERATION-FAILED naming OPERATION and TARGET. A condition that is already
a HOST-KIT-ERROR (including one raised by a nested %WITH-HOST-OPERATION) is
re-signalled unchanged so wrapping stays single-layered."
  `(handler-case (progn ,@body)
     (host-kit-error (condition) (error condition))
     (error (condition) (%signal-host-operation-failed ,operation ,target condition))))
