;;;; t/filesystem-test.lisp
(in-package #:cl-host-kit/test)

(defun %make-scratch-directory ()
  "A fresh, uniquely-named scratch directory under HOST-KIT's own
TEMPORARY-DIRECTORY, so filesystem tests can create and tear down real files
without touching anything outside of it."
  (ensure-directories-exist
   (merge-pathnames (format nil "cl-host-kit-fs-test-~D-~D/" (get-universal-time) (random 1000000))
                     (temporary-directory))))

(describe "file-exists-p / directory-exists-p"
  (it "file-exists-p returns the truename of an existing regular file"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (let ((file (merge-pathnames "a.txt" scratch)))
             (with-open-file (stream file :direction :output :if-exists :supersede)
               (write-string "x" stream))
             (expect (file-exists-p file) :to-be-truthy)
             (expect (directory-pathname-p (file-exists-p file)) :to-be-falsy))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "file-exists-p is NIL for a directory"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (expect (file-exists-p scratch) :to-be nil)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "file-exists-p is NIL for a missing path"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (expect (file-exists-p (merge-pathnames "nope.txt" scratch)) :to-be nil)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "directory-exists-p returns the truename of an existing directory"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (expect (directory-pathname-p (directory-exists-p scratch)) :to-be-truthy)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "directory-exists-p is NIL for a regular file"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (let ((file (merge-pathnames "a.txt" scratch)))
             (with-open-file (stream file :direction :output :if-exists :supersede)
               (write-string "x" stream))
             (expect (directory-exists-p file) :to-be nil))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

(describe "directory-files / subdirectories"
  (it "directory-files lists only the regular files, non-recursively"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (progn
             (with-open-file (s (merge-pathnames "a.txt" scratch)
                                 :direction :output :if-exists :supersede)
               (write-string "x" s))
             (with-open-file (s (merge-pathnames "noext" scratch)
                                 :direction :output :if-exists :supersede)
               (write-string "x" s))
             (ensure-directories-exist (merge-pathnames "child/" scratch))
             (let ((names (sort (mapcar #'file-namestring (directory-files scratch)) #'string<)))
               (expect names :to-equal (list "a.txt" "noext"))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "subdirectories lists only the immediate subdirectories, non-recursively"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (progn
             (ensure-directories-exist (merge-pathnames "child-a/" scratch))
             (ensure-directories-exist (merge-pathnames "child-b/grandchild/" scratch))
             (let ((names (sort (mapcar (lambda (p) (car (last (pathname-directory p))))
                                         (subdirectories scratch))
                                 #'string<)))
               (expect names :to-equal (list "child-a" "child-b"))))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

(describe "delete-directory-tree"
  (it "recursively deletes a non-empty directory"
    (let ((scratch (%make-scratch-directory)))
      (ensure-directories-exist (merge-pathnames "child/" scratch))
      (with-open-file (s (merge-pathnames "child/a.txt" scratch)
                          :direction :output :if-exists :supersede)
        (write-string "x" s))
      (delete-directory-tree scratch)
      (expect (directory-exists-p scratch) :to-be nil)))

  (it "signals by default when the directory does not exist"
    (signals host-operation-failed
      (delete-directory-tree "/definitely/does/not/exist/cl-host-kit-xyz")))

  (it "IF-DOES-NOT-EXIST :IGNORE silently succeeds when the directory is already gone"
    (expect (delete-directory-tree "/definitely/does/not/exist/cl-host-kit-xyz"
                                    :if-does-not-exist :ignore)
            :to-be nil))

  (it "VALIDATE T rejects a pathname that is not directory-form"
    (signals host-operation-failed
      (delete-directory-tree "/tmp/cl-host-kit-not-a-directory.txt" :validate t))))

(describe "rename-file-overwriting-target"
  (it "atomically overwrites an existing target"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (let ((source (merge-pathnames "source.txt" scratch))
                 (target (merge-pathnames "target.txt" scratch)))
             (with-open-file (s source :direction :output :if-exists :supersede)
               (write-string "new" s))
             (with-open-file (s target :direction :output :if-exists :supersede)
               (write-string "old" s))
             (rename-file-overwriting-target source target)
             (expect (file-exists-p source) :to-be nil)
             (expect (read-file-string target) :to-equal "new"))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

(describe "temporary-directory"
  (it "returns a directory-form pathname"
    (expect (directory-pathname-p (temporary-directory)) :to-be-truthy))

  (it "honors TMPDIR when set"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (progn
             (setf (getenv "TMPDIR") (namestring scratch))
             (expect (namestring (temporary-directory)) :to-equal (namestring scratch)))
        (setf (getenv "TMPDIR") nil)
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

(describe "read-file-string"
  (it "returns the entire file contents as a string"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (let ((file (merge-pathnames "a.txt" scratch)))
             (with-open-file (s file :direction :output :if-exists :supersede)
               (write-string "hello, world" s))
             (expect (read-file-string file) :to-equal "hello, world"))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "signals HOST-OPERATION-FAILED for a missing file"
    (signals host-operation-failed
      (read-file-string "/definitely/does/not/exist/cl-host-kit-xyz.txt"))))
