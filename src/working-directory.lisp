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
