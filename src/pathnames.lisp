;;;; src/pathnames.lisp
;;;;
;;;; Pathname coercion and predicates. The public contract is intentionally
;;;; direct and small; it does not reproduce UIOP's optional-argument surface.
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

(defun parent-directory-pathname (pathspec)
  "Return the parent directory of PATHSPEC as a directory-form pathname.
The filesystem root is its own parent. Relative pathnames with one component
return the relative default directory."
  (let* ((directory-pathname (pathname-directory-pathname pathspec))
         (directory (pathname-directory directory-pathname)))
    (if (or (null directory) (null (rest directory)))
        directory-pathname
        (make-pathname :directory (butlast directory)
                       :name nil
                       :type nil
                       :defaults directory-pathname))))

(defun truenamize (pathspec)
  "Return a canonical, absolute form of PATHSPEC, resolving symlinks where
possible. Unlike TRUENAME, this does not signal an error when PATHSPEC does
not (yet) exist: it resolves the nearest existing parent directory and
re-attaches the unresolved name and type."
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (or (probe-file pathname)
        (labels ((normalize-relative-directory (components)
                   ;; The unresolved suffix cannot contain a real symlink, so
                   ;; lexical cancellation is safe after resolving its parent.
                   (loop with normalized = nil
                         for component in components
                         do (cond
                              ((eq component :up)
                               (pop normalized))
                              ((eq component :current))
                              (t
                               (push component normalized)))
                         finally (return (nreverse normalized))))
                 (resolve-parent (directory unresolved-components)
                   (let ((resolved-directory (probe-file directory)))
                     (cond
                       (resolved-directory
                        (merge-pathnames
                         (make-pathname
                          :directory
                          (cons :relative
                                (normalize-relative-directory unresolved-components))
                          :name (pathname-name pathname)
                          :type (pathname-type pathname)
                          :version (pathname-version pathname))
                         resolved-directory))
                       (t
                        (let ((parent (parent-directory-pathname directory)))
                          (if (equal parent directory)
                              pathname
                              (resolve-parent
                               parent
                               (cons (car (last (pathname-directory directory)))
                                     unresolved-components)))))))))
          (resolve-parent (pathname-directory-pathname pathname) (list))))))

(defun %normalized-absolute-directory-components (pathspec)
  "Return PATHSPEC's absolute directory components without dot navigation."
  (loop with normalized = nil
        for component in
          (rest (pathname-directory
                 (ensure-directory-pathname
                  (ensure-absolute-pathname pathspec))))
        do (cond
             ((eq component :up)
              (when normalized
                (pop normalized)))
             ((eq component :current))
             (t
              (push component normalized)))
        finally (return (nreverse normalized))))

(defun pathname-within-p (pathspec directory &key (resolve-symlinks nil))
  "True when PATHSPEC is DIRECTORY itself or a descendant of DIRECTORY.

The comparison is lexical after absolute pathnames and dot navigation are
normalized. When RESOLVE-SYMLINKS is true, TRUENAMIZE resolves each path's
existing ancestors first, so links cannot escape DIRECTORY. This function
does not require PATHSPEC itself to exist."
  (check-type resolve-symlinks boolean)
  (let* ((pathname (ensure-absolute-pathname pathspec))
         (directory
           (ensure-directory-pathname (ensure-absolute-pathname directory)))
         (pathname (if resolve-symlinks (truenamize pathname) pathname))
         (directory
           (if resolve-symlinks
               (ensure-directory-pathname (truenamize directory))
               directory))
         (pathname-directory (pathname-directory-pathname pathname))
         (pathname-components
           (%normalized-absolute-directory-components pathname-directory))
         (directory-components
           (%normalized-absolute-directory-components directory)))
    (and (equal (pathname-host pathname-directory) (pathname-host directory))
         (equal (pathname-device pathname-directory) (pathname-device directory))
         (<= (length directory-components) (length pathname-components))
         (equal directory-components
                (subseq pathname-components 0 (length directory-components))))))

(defun relative-pathname (pathspec base)
  "Return PATHSPEC as a lexical pathname relative to directory BASE.

Both inputs are first made absolute. This function does not access the
filesystem, normalize dot components, or resolve symbolic links."
  (let* ((pathname (ensure-absolute-pathname pathspec))
         (base-directory
           (ensure-absolute-pathname (ensure-directory-pathname base)))
         (pathname-directory (pathname-directory pathname))
         (base-components (rest (pathname-directory base-directory)))
         (pathname-components (rest pathname-directory))
         (common-length
           (loop for base-component in base-components
                 for pathname-component in pathname-components
                 while (equal base-component pathname-component)
                 count t))
         (upward-components
           (loop repeat (- (length base-components) common-length)
                 collect :up))
         (relative-directory
           (append (list :relative)
                   upward-components
                   (nthcdr common-length pathname-components))))
    (make-pathname
     :directory relative-directory
     :name (pathname-name pathname)
     :type (pathname-type pathname)
     :version (pathname-version pathname)
     :defaults pathname)))
