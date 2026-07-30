;;;; src/pathnames.lisp
;;;;
;;;; Pathname coercion and predicates. uiop's equivalents (ENSURE-PATHNAME,
;;;; ENSURE-ABSOLUTE-PATHNAME, ...) accept a long tail of keyword arguments,
;;;; but this library deliberately supports only pathname designators and
;;;; ENSURE-ABSOLUTE-PATHNAME's positional defaults directory. These are
;;;; implemented against that narrower contract rather than uiop's full
;;;; surface.
(in-package #:host-kit)

(defun absolute-pathname-p (pathspec)
  "True when PATHSPEC (a pathname designator) denotes an absolute path."
  (eq (car (pathname-directory (pathname pathspec))) :absolute))

(defun directory-pathname-p (pathspec)
  "Return T if PATHSPEC identifies a directory pathname."
  (let ((pathname (pathname pathspec)))
    (not (or (pathname-name pathname) (pathname-type pathname)))))

(defun ensure-pathname (pathspec)
  "Coerce PATHSPEC (a string or pathname designator) into a PATHNAME."
  (pathname pathspec))

(defun ensure-directory-pathname (pathspec)
  "Return a directory-form PATHNAME for PATHSPEC. If PATHSPEC already denotes
  a directory, it is returned coerced but otherwise unchanged; otherwise its
  name and type are folded into the last directory component."
  (declare (optimize (speed 3) (safety 1) (debug 0)))
  (let ((pathname (pathname pathspec)))
    (if (not (or (pathname-name pathname) (pathname-type pathname))) pathname
      (make-pathname
        :directory
        (append
          (or (pathname-directory pathname) (list :relative))
          (list (file-namestring pathname)))
        :name
        nil
        :type
        nil
        :defaults
        pathname))))

(defun ensure-absolute-pathname (pathspec &optional (defaults *default-pathname-defaults*))
  "Return an absolute PATHNAME for PATHSPEC, merging it against DEFAULTS
  (a directory, defaulting to *DEFAULT-PATHNAME-DEFAULTS*) when PATHSPEC is
  relative."
  (declare (optimize (speed 3) (safety 1) (debug 0)))
  (let ((pathname (pathname pathspec)))
    (if (eq (car (pathname-directory pathname)) :absolute) pathname
      (merge-pathnames pathname (ensure-directory-pathname defaults)))))

(defun pathname-directory-pathname (pathspec)
  "Return the directory-only portion of PATHSPEC, stripping any name and type."
  (make-pathname :name nil :type nil :defaults (pathname pathspec)))

(defun %merge-unresolved-pathname (pathname resolved-directory unresolved-components)
  "Attach PATHNAME unresolved directory suffix to RESOLVED-DIRECTORY."
  (merge-pathnames
    (make-pathname
      :directory (cons :relative unresolved-components)
      :name (pathname-name pathname)
      :type (pathname-type pathname)
      :version (pathname-version pathname))
    resolved-directory))

(defun %truenamize-missing-pathname (pathname)
  "Resolve PATHNAME through its nearest existing parent with a binary search."
  (let* ((directory (pathname-directory-pathname pathname))
         (components (pathname-directory directory))
         (component-count (length components)))
    (labels ((directory-at (end)
               (make-pathname :directory (subseq components 0 end)
                              :name nil
                              :type nil
                              :defaults directory))
             (probe-directory (end)
               (probe-file (directory-at end))))
      ;; A missing parent makes every deeper prefix missing, so binary search it.
      (let ((lower 1)
            (upper component-count)
            (resolved-directory (probe-directory 1)))
        (loop while (< lower upper)
              for middle = (ceiling (+ lower upper) 2)
              for candidate = (probe-directory middle)
              if candidate
                do (setf lower middle
                         resolved-directory candidate)
              else
                do (setf upper (1- middle)))
        (%merge-unresolved-pathname pathname
                                    resolved-directory
                                    (nthcdr lower components))))))

(defun truenamize (pathspec)
  "Return a canonical, absolute form of PATHSPEC, resolving symlinks where
possible. Unlike TRUENAME, this does not signal an error when PATHSPEC does
not yet exist: it resolves the nearest existing parent directory and
re-attaches the unresolved path suffix."
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (or (probe-file pathname) (%truenamize-missing-pathname pathname))))
