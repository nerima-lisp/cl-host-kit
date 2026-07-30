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

(describe "with-current-directory"
  (it "scopes the current directory and restores it after an error"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-with-cwd-test/" (temporary-directory)))))
      (unwind-protect
           (progn
             (signals error
               (with-current-directory (scratch)
                 (expect (namestring (getcwd)) :to-equal (namestring (probe-file scratch)))
                 (error "scope failure")))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (chdir original)
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

(describe "call-with-current-directory"
  (it "restores the directory when its thunk signals an error"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-cps-cwd-test/" (temporary-directory)))))
      (unwind-protect
           (progn
             (signals error
               (call-with-current-directory scratch
                                            (lambda ()
                                              (expect (namestring (getcwd))
                                                      :to-equal
                                                      (namestring (probe-file scratch)))
                                              (error "scope failure"))))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (chdir original)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "rejects a non-function thunk before changing the directory"
    (let ((original (getcwd)))
      (signals error (call-with-current-directory (temporary-directory) nil))
      (expect (namestring (getcwd)) :to-equal (namestring original)))))
