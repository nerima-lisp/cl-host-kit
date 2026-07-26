;;;; t/working-directory-test.lisp
(in-package #:cl-host-kit/test)

(describe "getcwd"
  (it "returns a directory-form pathname"
    (expect (directory-pathname-p (getcwd)) :to-be-truthy)))

(describe "chdir"
  (it "changes the current working directory, observed via getcwd"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                     (merge-pathnames "cl-host-kit-chdir-test/" (temporary-directory)))))
      (unwind-protect
           (progn
             (chdir scratch)
             (expect (namestring (getcwd)) :to-equal (namestring (probe-file scratch))))
        (chdir original)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "signals HOST-OPERATION-FAILED for a directory that does not exist"
    (signals host-operation-failed (chdir "/definitely/does/not/exist/cl-host-kit-xyz"))))
