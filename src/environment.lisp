;;;; src/environment.lisp
;;;;
;;;; Environment-variable access and process termination. Every top-level
;;;; form is individually feature-gated (#+sbcl / #-sbcl), following
;;;; cl-tty-kit's precedent: the #-sbcl branch of each function still exists
;;;; and calls %UNSUPPORTED, so the public API is identical across
;;;; implementations and a non-SBCL caller gets a structured condition
;;;; instead of an undefined-function error.
(in-package #:host-kit)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

#+sbcl
(defun getenv (name)
  "Return the value of environment variable NAME as a string, or NIL if it is
unset."
  (sb-posix:getenv name))

#-sbcl
(defun getenv (name)
  (declare (ignore name))
  (%unsupported 'getenv))

#+sbcl
(defun (setf getenv) (value name)
  "Set environment variable NAME to VALUE (a string). A VALUE of NIL unsets
NAME instead."
  (%with-host-operation (:setf-getenv name)
    (if value
        (sb-posix:setenv name value 1)
        (sb-posix:unsetenv name)))
  value)

#-sbcl
(defun (setf getenv) (value name)
  (declare (ignore value name))
  (%unsupported 'getenv))

#+sbcl
(defun quit (&optional (code 0))
  "Terminate the current process with CODE (default 0), the HOST-KIT
equivalent of a modern language's os.exit()/process.exit(). Never returns."
  (sb-ext:exit :code code :abort nil))

#-sbcl
(defun quit (&optional (code 0))
  (declare (ignore code))
  (%unsupported 'quit))
