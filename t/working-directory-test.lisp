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

(describe "call-with-working-directory"
  (it "returns every value from the callback and restores the directory"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-working-directory-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (progn
             (expect (multiple-value-list
                      (call-with-working-directory
                       (lambda ()
                         (expect (namestring (getcwd))
                                 :to-equal (namestring (probe-file scratch)))
                         (values :first :second))
                       scratch))
                     :to-equal '(:first :second))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (chdir original)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "restores the directory when the callback signals"
    (let ((original (getcwd))
          (scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-working-directory-error-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (progn
             (handler-case
                 (call-with-working-directory
                  (lambda () (error "expected test failure"))
                  scratch)
               (error () nil))
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (chdir original)
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "requires a function callback"
    (signals type-error
      (call-with-working-directory :not-a-function (getcwd))))

  (it "supports nested scopes without deadlocking or restoring too early"
    (let ((original (getcwd))
          (outer (ensure-directories-exist
                  (merge-pathnames "cl-host-kit-working-directory-outer-test/"
                                   (temporary-directory))))
          (inner (ensure-directories-exist
                  (merge-pathnames "cl-host-kit-working-directory-inner-test/"
                                   (temporary-directory)))))
      (unwind-protect
           (progn
             (call-with-working-directory
              (lambda ()
                (expect (namestring (getcwd))
                        :to-equal (namestring (probe-file outer)))
                (call-with-working-directory
                 (lambda ()
                   (expect (namestring (getcwd))
                           :to-equal (namestring (probe-file inner))))
                 inner)
                (expect (namestring (getcwd))
                        :to-equal (namestring (probe-file outer))))
              outer)
             (expect (namestring (getcwd)) :to-equal (namestring original)))
        (chdir original)
        (delete-directory-tree outer :if-does-not-exist :ignore)
        (delete-directory-tree inner :if-does-not-exist :ignore)))))

(progn
  (describe "with-working-directory"
    (it "evaluates its body in the requested directory"
      (let ((original (getcwd))
            (scratch (ensure-directories-exist
                      (merge-pathnames "cl-host-kit-with-working-directory-test/"
                                       (temporary-directory)))))
        (unwind-protect
             (progn
               (expect (with-working-directory (scratch)
                         (namestring (getcwd)))
                       :to-equal (namestring (probe-file scratch)))
               (expect (namestring (getcwd)) :to-equal (namestring original)))
          (chdir original)
          (delete-directory-tree scratch :if-does-not-exist :ignore))))

    (it "preserves multiple values and restores the directory after an error"
      (let ((original (getcwd))
            (scratch (ensure-directories-exist
                      (merge-pathnames "cl-host-kit-with-working-directory-error-test/"
                                       (temporary-directory)))))
        (unwind-protect
             (progn
               (expect (multiple-value-list
                        (with-working-directory (scratch)
                          (expect (namestring (getcwd))
                                  :to-equal (namestring (probe-file scratch)))
                          (values :first :second)))
                       :to-equal '(:first :second))
               (signals error
                 (with-working-directory (scratch)
                   (error "expected test failure")))
               (expect (namestring (getcwd)) :to-equal (namestring original)))
          (chdir original)
          (delete-directory-tree scratch :if-does-not-exist :ignore)))))

  #+sbcl
  (describe "call-with-working-directory / threads"
    (it "serializes process-wide working-directory scopes"
      (let* ((outer (ensure-directories-exist
                     (merge-pathnames "cl-host-kit-working-directory-outer/"
                                      (temporary-directory))))
             (inner (ensure-directories-exist
                     (merge-pathnames "cl-host-kit-working-directory-inner/"
                                      (temporary-directory))))
             (outer-entered (sb-thread:make-semaphore :count 0))
             (release-outer (sb-thread:make-semaphore :count 0))
             (inner-entered (sb-thread:make-semaphore :count 0))
             (outer-thread nil)
             (inner-thread nil)
             (outer-joined-p nil)
             (inner-joined-p nil))
        (unwind-protect
             (progn
               (setf outer-thread
                     (sb-thread:make-thread
                      (lambda ()
                        (call-with-working-directory
                         (lambda ()
                           (sb-thread:signal-semaphore outer-entered)
                           (unless (sb-thread:wait-on-semaphore
                                    release-outer :timeout 5)
                             (error "Timed out waiting to release outer scope.")))
                         outer))))
               (expect (sb-thread:wait-on-semaphore outer-entered :timeout 5)
                       :to-be-truthy)
               (setf inner-thread
                     (sb-thread:make-thread
                      (lambda ()
                        (call-with-working-directory
                         (lambda ()
                           (sb-thread:signal-semaphore inner-entered))
                         inner))))
               (expect (sb-thread:wait-on-semaphore inner-entered :timeout 0.1)
                       :to-be nil)
               (sb-thread:signal-semaphore release-outer)
               (expect (sb-thread:wait-on-semaphore inner-entered :timeout 5)
                       :to-be-truthy)
               (sb-thread:join-thread outer-thread)
               (setf outer-joined-p t)
               (sb-thread:join-thread inner-thread)
               (setf inner-joined-p t))
          (sb-thread:signal-semaphore release-outer)
          (unless outer-joined-p
            (when outer-thread
              (ignore-errors (sb-thread:join-thread outer-thread))))
          (unless inner-joined-p
            (when inner-thread
              (ignore-errors (sb-thread:join-thread inner-thread))))
          (delete-directory-tree outer :if-does-not-exist :ignore)
          (delete-directory-tree inner :if-does-not-exist :ignore))))))
