;;;; src/filesystem.lisp
;;;;
;;;; Existence checks, non-recursive listing, deletion, renaming, temporary
;;;; directories, and whole-file reads. Existence and listing are built on
;;;; PROBE-FILE and CL:DIRECTORY rather than raw sb-posix stat/opendir calls:
;;;; PROBE-FILE already normalizes a directory target to directory-form (with
;;;; a trailing separator, regardless of how it was spelled), which is
;;;; the documented "truthy pathname or NIL" contract exposed here.
(in-package #:host-kit)

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
  (remove-if
    #'directory-pathname-p
    (directory
      (merge-pathnames
        (make-pathname :name :wild :type :wild)
        (ensure-directory-pathname pathspec)))))

(defun subdirectories (pathspec)
  "Return a list of directory-form pathnames for the immediate subdirectories
of directory PATHSPEC. Non-recursive."
  (directory
    (merge-pathnames
      (make-pathname :directory (quote (:relative :wild)) :name nil :type nil)
      (ensure-directory-pathname pathspec))))

(defun %validate-delete-directory-tree-pathspec (pathspec validate)
  (when validate
    (%with-host-operation
      (:delete-directory-tree pathspec)
      (unless (directory-pathname-p pathspec)
        (error "~S does not denote a directory" pathspec)))))

(defun delete-directory-tree (pathspec &key validate (if-does-not-exist :error))
  "Recursively delete the directory PATHSPEC. IF-DOES-NOT-EXIST is :ERROR
(the default) or :IGNORE, in which case a missing PATHSPEC is treated as
already-deleted rather than an error. VALIDATE, when true, requires the raw
PATHSPEC to be directory-form before anything is deleted."
  (%validate-delete-directory-tree-pathspec pathspec validate)
  (let ((pathname (ensure-directory-pathname pathspec)))
    (%with-host-operation
      (:delete-directory-tree pathname)
      (handler-case (sb-ext:delete-directory pathname :recursive t)
        (file-error (condition)
          (unless (and (eq if-does-not-exist :ignore)
                       (null (probe-file pathname)))
            (error condition))))))
  (values))

(defun rename-file-overwriting-target (source target)
  "Rename SOURCE to TARGET, atomically replacing TARGET if it already
exists. Built on POSIX rename(2) (via sb-posix:rename) rather than
CL:RENAME-FILE, since rename(2) already overwrites its destination
atomically."
  (%with-host-operation
    (:rename-file-overwriting-target (list source target))
    (sb-posix:rename (pathname source) (pathname target)))
  (values))

(defun temporary-directory ()
  "Return the system temporary directory as a directory-form pathname,
honoring TMPDIR when set and falling back to /tmp/ otherwise."
  (ensure-directory-pathname (or (getenv "TMPDIR") "/tmp/")))

(defun read-file-string (pathspec)
  "Return the entire UTF-8 contents of the file PATHSPEC as a string."
  (%with-host-operation
    (:read-file-string pathspec)
    (with-open-file (stream pathspec :direction :input :element-type (quote (unsigned-byte 8)))
      (let* ((length (file-length stream))
             (octets (make-array length :element-type (quote (unsigned-byte 8))))
             (end (read-sequence octets stream)))
        (sb-ext:octets-to-string octets :external-format :utf-8 :end end)))))
