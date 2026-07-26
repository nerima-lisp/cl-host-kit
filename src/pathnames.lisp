;;;; src/pathnames.lisp
;;;;
;;;; Pathname coercion and predicates. uiop's equivalents (ENSURE-PATHNAME,
;;;; ENSURE-ABSOLUTE-PATHNAME, ...) accept a long tail of keyword arguments,
;;;; but the org-wide call-site survey found none of them used anywhere in
;;;; nerima-lisp -- every call passes only the pathname designator, and
;;;; ENSURE-ABSOLUTE-PATHNAME's optional defaults directory is always
;;;; positional. These are implemented against exactly that narrower
;;;; contract rather than uiop's full surface.
(in-package #:host-kit)

(defun absolute-pathname-p (pathspec)
  "True when PATHSPEC (a pathname designator) denotes an absolute path."
  (eq (car (pathname-directory (pathname pathspec))) :absolute))

(defun directory-pathname-p (pathspec)
  "True when PATHSPEC (a pathname designator) denotes a directory, i.e. it
has neither a name nor a type component."
  (let ((pathname (pathname pathspec)))
    (and (null (pathname-name pathname))
         (null (pathname-type pathname)))))

(defun ensure-pathname (pathspec)
  "Coerce PATHSPEC (a string or pathname designator) into a PATHNAME."
  (pathname pathspec))

(defun ensure-directory-pathname (pathspec)
  "Return a directory-form PATHNAME for PATHSPEC. If PATHSPEC already denotes
a directory, it is returned coerced but otherwise unchanged; otherwise its
name and type are folded into the last directory component."
  (let ((pathname (pathname pathspec)))
    (if (directory-pathname-p pathname)
        pathname
        (make-pathname
         :directory (append (or (pathname-directory pathname) (list :relative))
                             (list (file-namestring pathname)))
         :name nil
         :type nil
         :defaults pathname))))

(defun ensure-absolute-pathname (pathspec &optional (defaults *default-pathname-defaults*))
  "Return an absolute PATHNAME for PATHSPEC, merging it against DEFAULTS
(a directory, defaulting to *DEFAULT-PATHNAME-DEFAULTS*) when PATHSPEC is
relative."
  (let ((pathname (pathname pathspec)))
    (if (absolute-pathname-p pathname)
        pathname
        (merge-pathnames pathname (ensure-directory-pathname defaults)))))

(defun pathname-directory-pathname (pathspec)
  "Return the directory-only portion of PATHSPEC, stripping any name and type."
  (make-pathname :name nil :type nil :defaults (pathname pathspec)))

(defun truenamize (pathspec)
  "Return a canonical, absolute form of PATHSPEC, resolving symlinks where
possible. Unlike TRUENAME, this does not signal an error when PATHSPEC does
not (yet) exist: it resolves the nearest existing parent directory and
re-attaches the unresolved name and type."
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (or (probe-file pathname)
        (let ((resolved-directory (probe-file (pathname-directory-pathname pathname))))
          (if resolved-directory
              ;; No :DEFAULTS here: a name/type-only pathname leaves DIRECTORY
              ;; unspecified so MERGE-PATHNAMES fills it in from
              ;; RESOLVED-DIRECTORY. Passing :DEFAULTS PATHNAME would instead
              ;; inherit PATHNAME's own (unresolved) directory, silently
              ;; discarding the resolution this function exists to do.
              (merge-pathnames (make-pathname :name (pathname-name pathname)
                                               :type (pathname-type pathname))
                                resolved-directory)
              pathname)))))
