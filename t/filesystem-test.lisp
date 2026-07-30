;;;; t/filesystem-test.lisp
(in-package #:cl-host-kit/test)

(defun %make-scratch-directory ()
  "A fresh, uniquely-named scratch directory under HOST-KIT's own
TEMPORARY-DIRECTORY, so filesystem tests can create and tear down real files
without touching anything outside of it."
  (ensure-directories-exist
    (merge-pathnames
      (format nil "cl-host-kit-fs-test-~D-~D/" (get-universal-time) (random 1000000))
      (temporary-directory))))

(defmacro %with-scratch-directory ((scratch) &body body)
  "Run BODY with a fresh SCRATCH directory, always cleaning it up afterwards."
  `(let ((,scratch (%make-scratch-directory)))
    (unwind-protect (progn
        ,@body)
      (delete-directory-tree ,scratch :if-does-not-exist :ignore))))

(describe
  "file-exists-p / directory-exists-p"
  (it
    "file-exists-p returns the truename of an existing regular file"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "a.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "x" stream))
        (expect (file-exists-p file) :to-be-truthy)
        (expect (directory-pathname-p (file-exists-p file)) :to-be-falsy))))
  (it
    "file-exists-p is NIL for a directory"
    (%with-scratch-directory (scratch) (expect (file-exists-p scratch) :to-be nil)))
  (it
    "file-exists-p is NIL for a missing path"
    (%with-scratch-directory
      (scratch)
      (expect (file-exists-p (merge-pathnames "nope.txt" scratch)) :to-be nil)))
  (it
    "directory-exists-p returns the truename of an existing directory"
    (%with-scratch-directory
      (scratch)
      (expect (directory-pathname-p (directory-exists-p scratch)) :to-be-truthy)))
  (it
    "directory-exists-p is NIL for a regular file"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "a.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "x" stream))
        (expect (directory-exists-p file) :to-be nil)))))

(describe
  "directory-files / subdirectories"
  (it
    "directory-files lists only the regular files, non-recursively"
    (%with-scratch-directory
      (scratch)
      (with-open-file (stream
          (merge-pathnames "a.txt" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (with-open-file (stream
          (merge-pathnames "noext" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (ensure-directories-exist (merge-pathnames "child/" scratch))
      (let ((names (sort (mapcar #'file-namestring (directory-files scratch)) #'string<)))
        (expect names :to-equal (list "a.txt" "noext")))))
  (it
    "subdirectories lists only the immediate subdirectories, non-recursively"
    (%with-scratch-directory
      (scratch)
      (ensure-directories-exist (merge-pathnames "child-a/" scratch))
      (ensure-directories-exist (merge-pathnames "child-b/grandchild/" scratch))
      (let ((names
            (sort
              (mapcar
                (lambda (pathname)
                  (car (last (pathname-directory pathname))))
                (subdirectories scratch))
              #'string<)))
        (expect names :to-equal (list "child-a" "child-b"))))))

(describe
  "delete-directory-tree"
  (it
    "recursively deletes a non-empty directory"
    (let ((scratch (%make-scratch-directory)))
      (ensure-directories-exist (merge-pathnames "child/" scratch))
      (with-open-file (stream
          (merge-pathnames "child/a.txt" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (delete-directory-tree scratch)
      (expect (directory-exists-p scratch) :to-be nil)))
  (it
    "signals by default when the directory does not exist"
    (signals
      host-operation-failed
      (delete-directory-tree "/definitely/does/not/exist/cl-host-kit-xyz")))
  (it
    "IF-DOES-NOT-EXIST :IGNORE silently succeeds when the directory was removed"
    (let ((scratch (%make-scratch-directory)))
      (delete-directory-tree scratch)
      (expect (delete-directory-tree scratch :if-does-not-exist :ignore) :to-be nil)))
  (it
    "IF-DOES-NOT-EXIST :IGNORE preserves errors for an existing regular file"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "ordinary-file.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "not a directory" stream))
        (signals
          host-operation-failed
          (delete-directory-tree file :if-does-not-exist :ignore))
        (expect (file-exists-p file) :to-be-truthy))))
  (it
    "VALIDATE T rejects a pathname that is not directory-form"
    (signals
      host-operation-failed
      (delete-directory-tree "/tmp/cl-host-kit-not-a-directory.txt" :validate t)))
  (it
    "VALIDATE T accepts and deletes a directory-form pathname"
    (%with-scratch-directory
      (scratch)
      (delete-directory-tree scratch :validate t)
      (expect (directory-exists-p scratch) :to-be nil))))

(describe
  "rename-file-overwriting-target"
  (it
    "atomically overwrites an existing target"
    (%with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target.txt" scratch)))
        (with-open-file (stream source :direction :output :if-exists :supersede)
          (write-string "new" stream))
        (with-open-file (stream target :direction :output :if-exists :supersede)
          (write-string "old" stream))
        (rename-file-overwriting-target source target)
        (expect (file-exists-p source) :to-be nil)
        (expect (read-file-string target) :to-equal "new"))))
  (it
    "wraps a missing-source failure"
    (%with-scratch-directory
      (scratch)
      (signals
        host-operation-failed
        (rename-file-overwriting-target
          (merge-pathnames "missing.txt" scratch)
          (merge-pathnames "target.txt" scratch))))))

(describe
  "temporary-directory"
  (it
    "returns a directory-form pathname"
    (expect (directory-pathname-p (temporary-directory)) :to-be-truthy))
  (it
    "honors TMPDIR when set"
    (%with-scratch-directory
      (scratch)
      (%with-restored-environment
        ("TMPDIR")
        (setf (getenv "TMPDIR") (namestring scratch))
        (expect (namestring (temporary-directory)) :to-equal (namestring scratch)))))
  (it
    "falls back to /tmp when TMPDIR is unset"
    (%with-restored-environment
      ("TMPDIR")
      (setf (getenv "TMPDIR") nil)
      (expect (namestring (temporary-directory)) :to-equal "/tmp/"))))

(describe
  "read-file-string"
  (it
    "returns an empty string for an empty file"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "empty.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (declare (ignore stream)))
        (expect (read-file-string file) :to-equal ""))))
  (it
    "returns all ASCII contents across multiple reads"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "a.txt" scratch))
            (contents (make-string 16385 :initial-element #\a)))
        (with-open-file (stream file :direction :output :if-exists :supersede :external-format :utf-8)
          (write-string contents stream))
        (expect (read-file-string file) :to-equal contents))))
  (it
    "returns UTF-8 contents exactly"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "utf8.txt" scratch))
            (contents "Héllö, 世界"))
        (with-open-file (stream file :direction :output :if-exists :supersede :external-format :utf-8)
          (write-string contents stream))
        (expect (read-file-string file) :to-equal contents))))
  (it
    "returns large UTF-8 contents exactly"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "large-utf8.txt" scratch))
            (contents (make-string 16385 :initial-element (code-char #x00E9))))
        (with-open-file (stream file :direction :output :if-exists :supersede :external-format :utf-8)
          (write-string contents stream))
        (expect (read-file-string file) :to-equal contents))))
  (it
    "wraps an invalid UTF-8 decoding failure"
    (%with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "invalid-utf8.bin" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede
                         :element-type (quote (unsigned-byte 8)))
          (write-sequence #(255) stream))
        (let ((condition
                (handler-case (progn (read-file-string file) nil)
                  (host-operation-failed (condition) condition))))
          (expect condition :to-be-truthy)
          (expect (host-operation-failed-operation condition) :to-equal :read-file-string)))))
  (it
    "signals HOST-OPERATION-FAILED for a missing file"
    (signals
      host-operation-failed
      (read-file-string "/definitely/does/not/exist/cl-host-kit-xyz.txt"))))

(describe
  "filesystem edge cases"
  (it
    "returns NIL for a missing directory"
    (let ((scratch
          (ensure-directories-exist
            (merge-pathnames "cl-host-kit-missing-directory-test/" (temporary-directory)))))
      (unwind-protect (expect (directory-exists-p (merge-pathnames "missing/" scratch)) :to-be nil)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))
  (it
    "VALIDATE T rejects an existing regular file"
    (let ((scratch
          (ensure-directories-exist
            (merge-pathnames "cl-host-kit-validate-file-test/" (temporary-directory)))))
      (unwind-protect (let ((file (merge-pathnames "ordinary-file.txt" scratch)))
          (with-open-file (stream file :direction :output :if-exists :supersede)
            (write-line "not a directory" stream))
          (signals host-operation-failed (delete-directory-tree file :validate t))
          (expect (file-exists-p file) :to-be-truthy))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))
