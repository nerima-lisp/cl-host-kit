;;;; src/filesystem.lisp
;;;;
;;;; Existence checks, non-recursive listing, deletion, renaming, temporary
;;;; directories, and whole-file reads. Existence and listing are built on
;;;; PROBE-FILE and CL:DIRECTORY rather than raw sb-posix stat/opendir calls:
;;;; PROBE-FILE already normalizes a directory target to directory-form (with
;;;; a trailing separator, regardless of how it was spelled), which is
;;;; exactly the "truthy pathname or NIL" contract every existing call site
;;;; in the org relies on.
(in-package #:host-kit)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun file-exists-p (pathspec)
  "Return the truename of PATHSPEC if it exists and is not a directory, else
NIL."
  (let ((truename (probe-file pathspec)))
    (and truename (not (directory-pathname-p truename)) truename)))

(defun directory-exists-p (pathspec)
  "Return the truename of PATHSPEC if it exists and is a directory, else
NIL."
  (let ((truename (probe-file pathspec)))
    (and truename (directory-pathname-p truename) truename)))

(defun directory-files (pathspec)
  "Return a list of pathnames for the regular files directly inside
directory PATHSPEC. Non-recursive: subdirectories are excluded."
  (remove-if #'directory-pathname-p
             (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                          (ensure-directory-pathname pathspec)))))

(defun subdirectories (pathspec)
  "Return a list of directory-form pathnames for the immediate subdirectories
of directory PATHSPEC. Non-recursive."
  (directory (merge-pathnames (make-pathname :directory '(:relative :wild) :name nil :type nil)
                               (ensure-directory-pathname pathspec))))

(defun delete-directory-tree (pathspec &key validate (if-does-not-exist :error))
  "Recursively delete the directory PATHSPEC. IF-DOES-NOT-EXIST is :ERROR
(the default) or :IGNORE, in which case a missing PATHSPEC is treated as
already-deleted rather than an error. VALIDATE, when true, additionally
requires PATHSPEC to be a directory-form pathname before anything is
deleted -- a guard against accidentally passing a bare file pathname."
  (let ((pathname (ensure-directory-pathname pathspec)))
    (%with-host-operation (:delete-directory-tree pathname)
      (when (and validate (not (directory-pathname-p pathname)))
        (error "~S does not denote a directory" pathname))
      (handler-case (sb-ext:delete-directory pathname :recursive t)
        (file-error ()
          (unless (eq if-does-not-exist :ignore)
            (error "~S does not exist" pathname))))))
  (values))

#+sbcl
(defun rename-file-overwriting-target (source target)
  "Rename SOURCE to TARGET, atomically replacing TARGET if it already
exists. Built on POSIX rename(2) (via sb-posix:rename) rather than
CL:RENAME-FILE, since rename(2) already overwrites its destination
atomically."
  (%with-host-operation (:rename-file-overwriting-target (list source target))
    (sb-posix:rename (pathname source) (pathname target)))
  (values))

#-sbcl
(defun rename-file-overwriting-target (source target)
  (declare (ignore source target))
  (%unsupported 'rename-file-overwriting-target))

(defun temporary-directory ()
  "Return the system temporary directory as a directory-form pathname,
honoring TMPDIR when set and falling back to /tmp/ otherwise."
  (ensure-directory-pathname (or (getenv "TMPDIR") "/tmp/")))

(defun read-file-string (pathspec)
  "Return the entire contents of the file PATHSPEC as a string."
  (%with-host-operation (:read-file-string pathspec)
    (with-open-file (stream pathspec :direction :input :external-format :utf-8)
      (let ((contents (make-string (file-length stream))))
        (let ((end (read-sequence contents stream)))
          (if (= end (length contents))
              contents
              (subseq contents 0 end)))))))
