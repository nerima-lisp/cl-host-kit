;;;; src/environment.lisp
;;;;
;;;; Environment-variable access and process termination for SBCL.
(in-package #:host-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun getenv (name)
  "Return the value of environment variable NAME as a string, or NIL if it is
unset."
  (sb-posix:getenv name))

(defun (setf getenv) (value name)
  "Set environment variable NAME to VALUE (a string). A VALUE of NIL unsets
NAME instead."
  (%with-host-operation (:setf-getenv name)
    (if value
        (sb-posix:setenv name value 1)
        (sb-posix:unsetenv name)))
  value)

(defun quit (&optional (code 0))
  "Terminate the current process with CODE (default 0), the HOST-KIT
equivalent of a modern language's os.exit()/process.exit(). Never returns."
  (sb-ext:exit :code code :abort nil))
