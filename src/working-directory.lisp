;;;; src/working-directory.lisp
;;;;
;;;; The process's current working directory. sb-posix:getcwd/chdir wrap
;;;; getcwd(3)/chdir(2) directly; GETCWD additionally normalizes the raw
;;;; string sb-posix returns into a directory-form pathname so callers can
;;;; MERGE-PATHNAMES against it without a separate coercion step.
(in-package #:host-kit)

#+sbcl
(defvar *working-directory-scope-lock*
  (sb-thread:make-mutex :name "host-kit working directory scope"))

#+sbcl
(defvar *working-directory-scope-lock-held-p* nil)

#+sbcl
(defun %call-with-working-directory-scope-lock (thunk)
  (if *working-directory-scope-lock-held-p*
      (funcall thunk)
      (sb-thread:with-mutex (*working-directory-scope-lock*)
        (let ((*working-directory-scope-lock-held-p* t))
          (funcall thunk)))))

#-sbcl
(defun %call-with-working-directory-scope-lock (thunk)
  (funcall thunk))

#+sbcl
(defun getcwd ()
  "Return the current working directory as a directory-form pathname."
  (%with-host-operation (:getcwd nil)
    (ensure-directory-pathname (sb-posix:getcwd))))

#-sbcl
(defun getcwd ()
  (%unsupported 'getcwd))

#+sbcl
(defun chdir (pathspec)
  "Change the current working directory to PATHSPEC (a pathname designator)."
  (%with-host-operation (:chdir pathspec)
    (sb-posix:chdir (pathname pathspec)))
  (values))

#-sbcl
(defun chdir (pathspec)
  (declare (ignore pathspec))
  (%unsupported 'chdir))

(defun call-with-working-directory (thunk pathspec)
  "Call THUNK with PATHSPEC as the current working directory.

The previous working directory is restored when THUNK returns or exits
non-locally. THUNK receives no arguments and its values are returned. Scoped
changes are serialized with other HOST-KIT working-directory scopes."
  (check-type thunk function)
  (%call-with-working-directory-scope-lock
   (lambda ()
     (let ((previous-directory (getcwd)))
       (chdir pathspec)
       (unwind-protect
            (funcall thunk)
         (chdir previous-directory))))))

(defmacro with-working-directory ((pathspec) &body body)
  "Evaluate BODY with PATHSPEC as the current working directory."
  `(call-with-working-directory (lambda () ,@body) ,pathspec))
