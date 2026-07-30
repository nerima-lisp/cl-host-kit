;;;; src/working-directory.lisp
;;;;
;;;; The process's current working directory. sb-posix:getcwd/chdir wrap
;;;; getcwd(3)/chdir(2) directly; GETCWD additionally normalizes the raw
;;;; string sb-posix returns into a directory-form pathname so callers can
;;;; MERGE-PATHNAMES against it without a separate coercion step.
(in-package #:host-kit)

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

(defun call-with-current-directory (pathspec thunk)
  "Call THUNK with PATHSPEC as the process current directory.

The original directory is restored during normal return, non-local exit, or
error, including an error raised while changing to PATHSPEC."
  (unless (functionp thunk)
    (error "Current-directory scope thunk must be a function, got ~S" thunk))
  (let ((original-directory (getcwd)))
    (unwind-protect
         (progn
           (chdir pathspec)
           (funcall thunk))
      (chdir original-directory))))

(defmacro with-current-directory ((pathspec) &body body)
  "Run BODY with the process current directory set to PATHSPEC, restoring the
previous directory during normal return, non-local exit, or error."
  `(call-with-current-directory ,pathspec (lambda () ,@body)))
