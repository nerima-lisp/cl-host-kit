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

(defun %environment-binding (binding)
  "Validate BINDING and return its name and value as two values."
  (unless (and (listp binding) (= (length binding) 2))
    (error "Environment binding must be (NAME VALUE), got ~S" binding))
  (destructuring-bind (name value) binding
    (unless (stringp name)
      (error "Environment variable name must be a string, got ~S" name))
    (unless (or (null value) (stringp value))
      (error "Environment variable value must be a string or NIL, got ~S" value))
    (values name value)))

(defun call-with-environment-variables (bindings thunk)
  "Call THUNK with BINDINGS applied to the process environment.

BINDINGS is a list of (NAME VALUE) pairs. NAME and non-NIL VALUE must be
strings; a NIL VALUE temporarily unsets NAME. Every original value is
restored in reverse order, including when setup or THUNK signals an error."
  (unless (functionp thunk)
    (error "Environment scope thunk must be a function, got ~S" thunk))
  (let ((entries
          (mapcar (lambda (binding)
                    (multiple-value-bind (name value) (%environment-binding binding)
                      (list name value (getenv name))))
                  bindings)))
    (unwind-protect
         (progn
           (dolist (entry entries)
             (setf (getenv (first entry)) (second entry)))
           (funcall thunk))
      (dolist (entry (reverse entries))
        (setf (getenv (first entry)) (third entry))))))

(defmacro with-environment-variables (bindings &body body)
  "Evaluate BINDINGS once, bind their environment variables for BODY, then
restore every original value. Each binding is a two-element list (NAME VALUE);
a VALUE of NIL temporarily unsets NAME."
  (dolist (binding bindings)
    (unless (and (listp binding) (= (length binding) 2))
      (error "Environment binding must be (NAME VALUE), got ~S" binding)))
  `(call-with-environment-variables
       (list ,@(mapcar (lambda (binding)
                         `(list ,(first binding) ,(second binding)))
                       bindings))
     (lambda () ,@body)))

#+sbcl
(defun quit (&optional (code 0))
  "Terminate the current process with CODE (default 0), the HOST-KIT
equivalent of a modern language's os.exit()/process.exit(). Never returns."
  (sb-ext:exit :code code :abort nil))

#-sbcl
(defun quit (&optional (code 0))
  (declare (ignore code))
  (%unsupported 'quit))
