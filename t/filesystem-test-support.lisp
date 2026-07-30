;;;; t/filesystem-test-support.lisp
(in-package #:cl-host-kit/test)

(defmacro with-scratch-directory ((pathname) &body body)
  "Run BODY in an isolated directory and remove it even after a test failure."
  `(call-with-temporary-directory
    (lambda (,pathname)
      ,@body)
    :prefix "cl-host-kit-test-"))

(defmacro with-function-redefinition ((name function) &body body)
  "Run BODY with NAME temporarily bound to FUNCTION as its global definition."
  (let ((original (gensym "ORIGINAL-")))
    `(let ((,original (symbol-function ,name)))
      (unwind-protect (progn
          (setf (symbol-function ,name) ,function)
          ,@body)
        (setf (symbol-function ,name) ,original)))))
