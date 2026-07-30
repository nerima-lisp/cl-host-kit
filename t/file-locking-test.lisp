;;;; t/file-locking-test.lisp
(in-package #:cl-host-kit/test)

(defun %child-lock-exit-code (pathspec)
  (let* ((program (namestring sb-ext:*runtime-pathname*))
         (form (format nil
                       "(with-open-file (stream ~S :direction :io :if-exists :overwrite)~
                          (handler-case~
                              (progn~
                                (sb-posix:lockf (sb-sys:fd-stream-fd stream) sb-posix:f-tlock 0)~
                                (sb-ext:exit :code 0))~
                            (sb-posix:syscall-error (condition)~
                              (declare (ignore condition))~
                              (sb-ext:exit :code 1))))"
                       (namestring pathspec))))
    (process-result-exit-code
     (run-program program
                  (list "--noinform"
                        "--non-interactive"
                        "--eval" "(require :sb-posix)"
                        "--eval" form)
                  :timeout 10))))

(defun %start-lock-holder (pathspec ready-pathspec)
  (let* ((program (namestring sb-ext:*runtime-pathname*))
         (form (format nil
                       "(with-open-file (stream ~S :direction :io :if-exists :overwrite)~
                          (sb-posix:lockf (sb-sys:fd-stream-fd stream) sb-posix:f-lock 0)~
                          (with-open-file (ready ~S :direction :output :if-exists :supersede)~
                            (write-line \"ready\" ready))~
                          (sleep 30))"
                       (namestring pathspec)
                       (namestring ready-pathspec))))
    (sb-ext:run-program program
                        (list "--noinform"
                              "--non-interactive"
                              "--eval" "(require :sb-posix)"
                              "--eval" form)
                        :wait nil
                        :output nil
                        :error nil)))

(defun %wait-for-lock-holder (ready-pathspec)
  (let ((deadline (+ (get-internal-real-time)
                     internal-time-units-per-second)))
    (loop
      (when (probe-file ready-pathspec)
        (return t))
      (when (>= (get-internal-real-time) deadline)
        (error "Lock holder did not become ready."))
      (sleep 0.01d0))))

(defun %same-process-lock-conflict-outcome (pathspec &key (wait t) timeout)
  (let ((attempted (sb-thread:make-semaphore :count 0))
        (outcome nil)
        (worker nil))
    (unwind-protect
         (with-open-file (stream pathspec :direction :io :if-exists :overwrite)
           (with-advisory-file-lock (stream)
             (setf worker
                   (sb-thread:make-thread
                    (lambda ()
                      (sb-thread:signal-semaphore attempted)
                      (setf outcome
                            (handler-case
                                (with-open-file (other pathspec
                                                      :direction :io
                                                      :if-exists :overwrite)
                                  (with-advisory-file-lock
                                      (other :wait wait :timeout timeout)
                                    :acquired))
                              (file-lock-timeout () :timed-out)
                              (host-operation-failed () :unavailable))))))
             (sb-thread:wait-on-semaphore attempted)
             (sb-thread:join-thread worker)
             (setf worker nil)
             outcome))
      (when worker
        (sb-thread:join-thread worker)))))

(describe "call-with-advisory-file-lock / with-advisory-file-lock"
  (it "preserves all callback values and binds the locked stream"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (stream target :direction :io :if-exists :overwrite)
          (expect (multiple-value-list
                   (call-with-advisory-file-lock
                    (lambda (locked-stream)
                      (expect locked-stream :to-be stream)
                      (values :first :second))
                    stream))
                  :to-equal '(:first :second))))))

  (it "rejects invalid stream bindings during macroexpansion"
    (signals error (macroexpand-1 '(with-advisory-file-lock (42) nil)))
    (signals error (macroexpand-1 '(with-advisory-file-lock (nil) nil)))
    (signals error (macroexpand-1 '(with-advisory-file-lock (t) nil)))
    (signals error (macroexpand-1 '(with-file-lock (42 "ignored") nil)))
    (signals error (macroexpand-1 '(with-file-lock (nil "ignored") nil)))
    (signals error (macroexpand-1 '(with-file-lock (t "ignored") nil))))

  (it "rejects a non-file-descriptor stream"
    (signals type-error
      (call-with-advisory-file-lock #'identity
                                    (make-string-input-stream "contents"))))

  (it "rejects a closed file stream"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (with-open-file (stream target :direction :io :if-does-not-exist :create)
          (close stream)
          (signals type-error
            (call-with-advisory-file-lock #'identity stream))))))

  (it "validates the callback, wait option, timeout, and mode"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (with-open-file (stream target :direction :io :if-does-not-exist :create)
          (signals type-error
            (call-with-advisory-file-lock :not-a-function stream))
          (signals type-error
            (call-with-advisory-file-lock #'identity stream :wait :sometimes))
          (signals type-error
            (call-with-advisory-file-lock #'identity stream :timeout -1))
          (signals type-error
            (call-with-advisory-file-lock #'identity stream :mode :write))))))

  (it "propagates non-conflict lock acquisition errors"
    (signals sb-posix:syscall-error
      (host-kit::%acquire-advisory-file-lock -1 t 0.01d0)))

    (it "accepts a nonblocking lock when it is available"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (stream target :direction :io :if-exists :overwrite)
          (expect (with-advisory-file-lock (stream :wait nil)
                    :locked)
                    :to-equal :locked)))))

    (it "keeps an enclosing lock held across a nested scope on the same stream"
      (with-scratch-directory (scratch)
        (let ((target (merge-pathnames "locked.txt" scratch)))
          (write-file-string "contents" target)
          (with-open-file (outer target :direction :io :if-exists :overwrite)
            (with-advisory-file-lock (outer)
              (with-advisory-file-lock (outer)
                (expect (%child-lock-exit-code target) :to-equal 1))
              (expect (%child-lock-exit-code target) :to-equal 1)))
          (expect (%child-lock-exit-code target) :to-equal 0))))

  (it "rejects a nested lock on another descriptor for the same file"
      (with-scratch-directory (scratch)
        (let ((target (merge-pathnames "locked.txt" scratch)))
          (write-file-string "contents" target)
          (with-open-file (outer target :direction :io :if-exists :overwrite)
            (with-open-file (inner target :direction :io :if-exists :overwrite)
              (with-advisory-file-lock (outer)
                (signals host-operation-failed
                  (with-advisory-file-lock (inner)
                    :unreachable))
                (expect (%child-lock-exit-code target) :to-equal 1))))
          (expect (%child-lock-exit-code target) :to-equal 0))))

  (it "allows shared locks on distinct descriptors in the same process"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (outer target :direction :io :if-exists :overwrite)
          (with-open-file (inner target :direction :io :if-exists :overwrite)
            (with-advisory-file-lock (outer :mode :shared)
              (expect (with-advisory-file-lock (inner :mode :shared :wait nil)
                        :shared)
                      :to-equal :shared)))))))

  (it "rejects an exclusive lock while a shared lock is held"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (outer target :direction :io :if-exists :overwrite)
          (with-open-file (inner target :direction :io :if-exists :overwrite)
            (with-advisory-file-lock (outer :mode :shared)
              (signals host-operation-failed
                (with-advisory-file-lock (inner :wait nil)
                  :unreachable))))))))

  (it "times out another thread waiting for the same process lock"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (expect (%same-process-lock-conflict-outcome target :timeout 0.03d0)
                :to-equal :timed-out))))

  (it "rejects another thread's nonblocking request for the same process lock"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (expect (%same-process-lock-conflict-outcome target :wait nil)
                :to-equal :unavailable))))

  (it "fails immediately for a conflicting nonblocking lock"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (stream target :direction :io :if-exists :overwrite)
          (with-advisory-file-lock (stream)
            (expect (%child-lock-exit-code target) :to-equal 1)))
        (expect (%child-lock-exit-code target) :to-equal 0))))

  (it "blocks an external exclusive lock while a shared lock is held"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (stream target :direction :io :if-exists :overwrite)
          (with-advisory-file-lock (stream :mode :shared)
            (expect (%child-lock-exit-code target) :to-equal 1)))
        (expect (%child-lock-exit-code target) :to-equal 0))))

  (it "signals a bounded timeout for a conflicting lock"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "locked.txt" scratch))
             (ready (merge-pathnames "lock-ready" scratch))
             (holder nil))
        (write-file-string "contents" target)
        (unwind-protect
             (progn
               (setf holder (%start-lock-holder target ready))
               (%wait-for-lock-holder ready)
               (with-open-file (stream target :direction :io :if-exists :overwrite)
                 (expect (handler-case
                             (call-with-advisory-file-lock
                              (lambda (locked-stream)
                                (declare (ignore locked-stream))
                                :acquired)
                              stream
                              :timeout 0.03d0)
                           (file-lock-timeout (condition)
                             (file-lock-timeout-seconds condition)))
                         :to-equal 0.03d0)))
          (when holder
            (ignore-errors (sb-ext:process-kill holder 15))
            (ignore-errors (sb-ext:process-wait holder)))))))

  (it "releases the original range after callback failure and repositioning"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (write-file-string "contents" target)
        (with-open-file (stream target :direction :io :if-exists :overwrite)
          (signals error
            (call-with-advisory-file-lock
             (lambda (locked-stream)
               (file-position locked-stream 2)
               (error "expected test failure"))
             stream)))
         (expect (%child-lock-exit-code target) :to-equal 0)))))

(describe "call-with-file-lock / with-file-lock"
  (it "creates, locks, and closes a pathname-scoped stream"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch))
            (locked-stream nil))
        (expect (multiple-value-list
                 (call-with-file-lock
                  (lambda (stream)
                    (setf locked-stream stream)
                    (write-string "contents" stream)
                    (expect (%child-lock-exit-code target) :to-equal 1)
                    (values :first :second))
                  target))
                :to-equal '(:first :second))
        (expect (read-file-string target) :to-equal "contents")
        (expect (open-stream-p locked-stream) :to-be nil)
        (expect (%child-lock-exit-code target) :to-equal 0))))

  (it "binds the stream and preserves macro body values"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (expect (multiple-value-list
                 (with-file-lock (stream target)
                   (expect (streamp stream) :to-be t)
                   (values :first :second)))
                :to-equal '(:first :second)))))

  (it "validates options before creating a target"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (signals type-error
          (call-with-file-lock :not-a-function target))
        (signals type-error
          (call-with-file-lock #'identity target :wait :no))
        (signals type-error
          (call-with-file-lock #'identity target :timeout -1))
        (signals type-error
          (call-with-file-lock #'identity target :mode :invalid))
        (expect (path-exists-p target) :to-be nil))))

  (it "releases the lock after callback failure"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "locked.txt" scratch)))
        (signals error
          (call-with-file-lock
           (lambda (stream)
             (write-string "contents" stream)
             (error "expected test failure"))
           target))
        (expect (%child-lock-exit-code target) :to-equal 0)))))
