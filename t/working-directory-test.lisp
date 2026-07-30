;;;; t/working-directory-test.lisp
(in-package #:cl-host-kit/test)

(defmacro %with-restored-working-directory (() &body body) `(let ((original (getcwd))) (unwind-protect (progn ,@body) (chdir original))))

(describe "getcwd"
  (it "returns a directory-form pathname"
    (expect (directory-pathname-p (getcwd)) :to-be-truthy)))

(describe "chdir"
  (it "changes the current working directory, observed via getcwd"
    (let ((scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-chdir-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (%with-restored-working-directory ()
             (chdir scratch)
             (expect (namestring (getcwd))
                     :to-equal (namestring (probe-file scratch))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))
  (it "restores nested working directories"
    (let ((original (getcwd))
          (first (ensure-directories-exist
                  (merge-pathnames "cl-host-kit-chdir-first/"
                                   (temporary-directory))))
          (second (ensure-directories-exist
                   (merge-pathnames "cl-host-kit-chdir-second/"
                                    (temporary-directory)))))
      (unwind-protect
           (progn
             (%with-restored-working-directory ()
               (chdir first)
               (%with-restored-working-directory ()
                 (chdir second)
                 (expect (namestring (getcwd))
                         :to-equal (namestring (probe-file second))))
               (expect (namestring (getcwd))
                       :to-equal (namestring (probe-file first))))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (delete-directory-tree first :if-does-not-exist :ignore)
        (delete-directory-tree second :if-does-not-exist :ignore))))
  (it "preserves multiple values and restores the directory"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-chdir-values/"
                                     (temporary-directory)))))
      (unwind-protect
           (progn
             (multiple-value-bind (first second)
                 (%with-restored-working-directory ()
                   (chdir scratch)
                   (values :first :second))
               (expect first :to-equal :first)
               (expect second :to-equal :second))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))
  (it "restores the directory after an error"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-chdir-error/"
                                     (temporary-directory)))))
      (unwind-protect
           (progn
             (handler-case
                 (%with-restored-working-directory ()
                   (chdir scratch)
                   (error "expected test error"))
               (error () nil))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))
  (it "signals HOST-OPERATION-FAILED for a directory that does not exist"
    (signals host-operation-failed
      (chdir "/definitely/does/not/exist/cl-host-kit-xyz"))))
