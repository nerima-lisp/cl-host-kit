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
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

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
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (let ((file (merge-pathnames "not-a-directory.txt" scratch)))
             (with-open-file (s file :direction :output :if-exists :supersede)
               (write-string "x" s))
             (signals host-operation-failed
               (delete-directory-tree file :validate t))
             (expect (file-exists-p file) :to-be-truthy))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

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

(describe "with-temporary-file / call-with-temporary-file"
  (it "writes through the stream and deletes the file after the scope"
    (let (temporary-pathname)
      (expect (with-temporary-file (:stream stream :pathname pathname)
                (write-string "temporary contents" stream)
                :close-stream
                (setf temporary-pathname pathname)
                (read-file-string pathname))
              :to-equal "temporary contents")
      (expect (file-exists-p temporary-pathname) :to-be nil)))

  (it "supports pathname-only scopes and caller-controlled names"
    (let ((scratch (%make-scratch-directory)))
      (unwind-protect
           (with-temporary-file (:pathname pathname
                                 :directory scratch
                                 :prefix "host-kit-"
                                 :suffix ".data"
                                 :type :unspecific)
             (expect (file-exists-p pathname) :to-be-truthy)
             (expect (string-prefix-p "host-kit-" (file-namestring pathname))
                     :to-be-truthy)
             (expect (search ".data" (file-namestring pathname)) :to-be-truthy))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "keeps the file only when KEEP evaluates true"
    (let (temporary-pathname)
      (unwind-protect
           (progn
             (with-temporary-file (:pathname pathname :keep t)
               (setf temporary-pathname pathname))
             (expect (file-exists-p temporary-pathname) :to-be-truthy))
        (when temporary-pathname
          (ignore-errors (delete-file temporary-pathname))))))

  (it "deletes a file when the body signals an error"
    (let (temporary-pathname)
      (signals error
        (with-temporary-file (:pathname pathname)
          (setf temporary-pathname pathname)
          (error "temporary-file test failure")))
      (expect (file-exists-p temporary-pathname) :to-be nil)))

  (it "passes the requested stream and pathname to CALL-WITH-TEMPORARY-FILE"
    (let (temporary-pathname)
      (expect (call-with-temporary-file
               (lambda (stream pathname)
                 (setf temporary-pathname pathname)
                 (write-string "call helper" stream)
                 pathname))
              :to-equal temporary-pathname)
      (expect (file-exists-p temporary-pathname) :to-be nil))))

  (it "runs AFTER after closing the temporary file stream"
    (let (temporary-pathname)
      (expect (call-with-temporary-file
               (lambda (stream pathname)
                 (declare (ignore pathname))
                 (write-string "after hook" stream))
               :after (lambda (pathname)
                        (setf temporary-pathname pathname)
                        (read-file-string pathname)))
              :to-equal "after hook")
      (expect (file-exists-p temporary-pathname) :to-be nil)))

  (it "retries a colliding exclusive-create name"
    (let ((scratch (%make-scratch-directory))
          (state (make-random-state t)))
      (unwind-protect
           (let* ((counter (let ((*random-state* (make-random-state state)))
                             (random (expt 36 8))))
                  (collision (merge-pathnames (format nil "collision-~36R" counter) scratch))
                  created-pathname)
             (with-open-file (stream collision :direction :output :if-exists :error)
               (write-string "already allocated" stream))
             (let ((*random-state* (make-random-state state)))
               (call-with-temporary-file
                (lambda (pathname)
                  (setf created-pathname pathname))
                :want-stream-p nil
                :directory scratch
                :prefix "collision-"
                :suffix nil
                :type :unspecific
                :attempts 2))
             (expect created-pathname :not :to-equal collision)
             (expect (file-exists-p collision) :to-be-truthy)
             (expect (file-exists-p created-pathname) :to-be nil))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "signals a structured failure when collision retries are exhausted"
    (let ((scratch (%make-scratch-directory))
          (state (make-random-state t)))
      (unwind-protect
           (let* ((counter (let ((*random-state* (make-random-state state)))
                             (random (expt 36 8))))
                  (collision (merge-pathnames (format nil "collision-~36R" counter) scratch)))
             (with-open-file (stream collision :direction :output :if-exists :error)
               (write-string "already allocated" stream))
             (let ((*random-state* (make-random-state state)))
               (signals host-operation-failed
                 (call-with-temporary-file nil
                                           :directory scratch
                                           :prefix "collision-"
                                           :suffix nil
                                           :type :unspecific
                                           :attempts 1)))
             (expect (file-exists-p collision) :to-be-truthy))
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

(describe "octet files"
  (it "writes and reads octets atomically"
    (let* ((directory (%make-scratch-directory))
           (target (merge-pathnames "bytes.bin" directory))
           (octets (make-array 4
                               :element-type '(unsigned-byte 8)
                               :initial-contents '(0 1 127 255))))
      (unwind-protect
           (progn
             (expect (write-file-octets octets target)
                     :to-equal
                     (ensure-absolute-pathname target))
             (expect (coerce (read-file-octets target) 'list)
                     :to-equal
                     '(0 1 127 255)))
        (delete-directory-tree directory))))

  (it "signals HOST-OPERATION-FAILED for a missing file"
    (signals host-operation-failed
      (read-file-octets "/definitely/does/not/exist/cl-host-kit-xyz.bin"))))

(describe "atomic output files"
  (it "replaces a target after closing the temporary output stream"
    (let* ((directory (%make-scratch-directory))
           (target (merge-pathnames "published.txt" directory)))
      (unwind-protect
           (progn
             (with-open-file (stream target :direction :output
                                            :if-exists :supersede)
               (write-string "old" stream))
             (expect
              (multiple-value-list
               (call-with-atomic-output-file
                target
                (lambda (stream)
                  (write-string "new" stream)
                  (values :first :second))))
              :to-equal
              '(:first :second))
             (expect (read-file-string target) :to-equal "new"))
        (delete-directory-tree directory))))

  (it "leaves an existing target unchanged when the writer fails"
    (let* ((directory (%make-scratch-directory))
           (target (merge-pathnames "published.txt" directory)))
      (unwind-protect
           (progn
             (with-open-file (stream target :direction :output
                                            :if-exists :supersede)
               (write-string "old" stream))
             (signals error
               (call-with-atomic-output-file
                target
                (lambda (stream)
                  (write-string "new" stream)
                  (error "writer failed"))))
             (expect (read-file-string target) :to-equal "old")
             (let ((files (directory-files directory)))
               (expect (length files) :to-equal 1)
               (expect (file-namestring (first files))
                       :to-equal
                       "published.txt")))
        (delete-directory-tree directory))))

  (it "provides a lexical output-stream macro"
    (let* ((directory (%make-scratch-directory))
           (target (merge-pathnames "macro.txt" directory)))
      (unwind-protect
           (progn
             (with-atomic-output-file (stream target)
               (write-string "macro" stream))
             (expect (read-file-string target) :to-equal "macro"))
        (delete-directory-tree directory))))

  (it "writes strings atomically and returns an absolute pathname"
    (let* ((directory (%make-scratch-directory))
           (target (merge-pathnames "string.txt" directory)))
      (unwind-protect
           (let ((result (write-file-string "contents" target)))
             (expect result :to-equal (ensure-absolute-pathname target))
             (expect (read-file-string target) :to-equal "contents"))
        (delete-directory-tree directory)))))
