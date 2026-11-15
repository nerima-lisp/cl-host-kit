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

  (it-each ((42) (nil) (t))
      "rejects ~S as a WITH-ADVISORY-FILE-LOCK stream binding during macroexpansion"
      (invalid-stream)
    (signals error (macroexpand-1 `(with-advisory-file-lock (,invalid-stream) nil))))

  (it-each ((42) (nil) (t))
      "rejects ~S as a WITH-FILE-LOCK stream binding during macroexpansion"
      (invalid-stream)
    (signals error (macroexpand-1 `(with-file-lock (,invalid-stream "ignored") nil))))

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


(describe "retained file locks"
  (it "retains a lock until explicit release and safely queries its own lock"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "lease.lock" scratch))
             (lock (try-acquire-file-lock target)))
        (unwind-protect
             (progn
               (expect (typep lock 'file-lock) :to-be t)
               (expect (logand #o777 (file-metadata-mode (file-metadata target))) :to-equal #o600)
               (write-line "metadata" (file-lock-stream lock))
               (finish-output (file-lock-stream lock))
               (expect (%child-lock-exit-code target) :to-equal 1)
               (expect (file-lock-held-by-other-process-p target) :to-be nil)
               (signals host-operation-failed (try-acquire-file-lock target))
               (expect (%child-lock-exit-code target) :to-equal 1)
               (expect (release-file-lock lock) :to-be t)
               (expect (release-file-lock lock) :to-be nil)
               (expect (open-stream-p (file-lock-stream lock)) :to-be nil)
               (expect (%child-lock-exit-code target) :to-equal 0))
          (release-file-lock lock)))))
  (it "observes a real other process and recovers after its exit"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "external.lock" scratch))
             (ready (merge-pathnames "ready" scratch))
             (holder nil))
        (write-file-string "" target)
        (unwind-protect
             (progn
               (setf holder (%start-lock-holder target ready))
               (%wait-for-lock-holder ready)
               (expect (file-lock-held-by-other-process-p target) :to-be t)
               (expect (try-acquire-file-lock target) :to-be nil)
               (sb-ext:process-kill holder 15)
               (sb-ext:process-wait holder)
               (setf holder nil)
               (expect (file-lock-held-by-other-process-p target) :to-be nil)
               (let ((lock (try-acquire-file-lock target)))
                 (expect (typep lock 'file-lock) :to-be t)
                 (release-file-lock lock)))
          (when holder
            (sb-ext:process-kill holder 15)
            (sb-ext:process-wait holder))))))
  (it "does not create an absent path when querying and wraps OS failures"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "absent.lock" scratch)))
        (expect (file-lock-held-by-other-process-p target) :to-be nil)
        (expect (path-exists-p target) :to-be nil)
        (signals host-operation-failed (try-acquire-file-lock scratch))
        (signals type-error (try-acquire-file-lock target :mode -1))
        (signals type-error (release-file-lock nil))))))


(describe "retained file lock lifecycle"
  (it "releases a retained lock when its owner process exits without cleanup"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "exited.lock" scratch))
             (root (asdf:system-source-directory "cl-host-kit"))
             (form (format nil
                           "(progn (asdf:initialize-source-registry '(:source-registry (:directory ~S) :ignore-inherited-configuration)) (asdf:load-system \"cl-host-kit\") (unless (uiop:symbol-call :host-kit :try-acquire-file-lock ~S) (error \"No lock\")) (sb-ext:exit :code 0))"
                           (namestring root) (namestring target))))
        (let ((result (run-program (namestring sb-ext:*runtime-pathname*)
                                   (list "--noinform" "--non-interactive"
                                         "--eval" "(require :asdf)" "--eval" form)
                                   :timeout 10)))
          (expect (process-result-exit-code result) :to-equal 0))
        (expect (file-lock-held-by-other-process-p target) :to-be nil)
        (let ((lock (try-acquire-file-lock target)))
          (expect (typep lock 'file-lock) :to-be t)
          (release-file-lock lock)))))
  (it "permits another thread to release the owned stream"
    (with-scratch-directory (scratch)
      (let ((lock (try-acquire-file-lock (merge-pathnames "thread.lock" scratch))))
        (unwind-protect
             (expect (sb-thread:join-thread
                      (sb-thread:make-thread (lambda () (release-file-lock lock))) :timeout 2)
                     :to-be t)
          (release-file-lock lock))))))


(describe "retained file lock release ordering"
  (it "flushes metadata before releasing the OS lock"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "metadata.lock" scratch))
             (lock (try-acquire-file-lock target))
             (unlock (symbol-function 'host-kit::%release-advisory-file-lock))
             (observed nil))
        (unwind-protect
             (progn
               (write-string "unflushed metadata" (file-lock-stream lock))
               (setf (symbol-function 'host-kit::%release-advisory-file-lock)
                     (lambda (fd start)
                       ;; Read through a child: opening another local fd drops POSIX locks.
                       (let ((result (run-program (namestring sb-ext:*runtime-pathname*)
                                                  (list "--noinform" "--non-interactive"
                                                        "--eval" "(require :asdf)"
                                                        "--eval" (format nil
                                                                         "(write-string (uiop:read-file-string ~S))"
                                                                         (namestring target))))))
                         (setf observed (process-result-stdout result)))
                       (funcall unlock fd start)))
               (release-file-lock lock)
               (expect observed :to-equal "unflushed metadata"))
          (setf (symbol-function 'host-kit::%release-advisory-file-lock) unlock)
          (release-file-lock lock)))))
  (it "retires the registry after a close failure and propagates that failure"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "close-error.lock" scratch))
             (lock (try-acquire-file-lock target))
             (stream (file-lock-stream lock))
             (original (symbol-function 'close))
             (injected nil))
        (unwind-protect
             (progn
               (sb-ext:without-package-locks
                 (setf (symbol-function 'close)
                       (lambda (candidate &key abort)
                         (prog1 (funcall original candidate :abort abort)
                           (when (and (eq candidate stream) (not injected))
                             (setf injected t)
                             (error "injected close failure"))))))
               (signals host-operation-failed (release-file-lock lock))
               (expect injected :to-be t)
               (expect (release-file-lock lock) :to-be nil)
               (expect (open-stream-p stream) :to-be nil)
               (let ((next (try-acquire-file-lock target)))
                 (expect (typep next 'file-lock) :to-be t)
                 (release-file-lock next)))
          (sb-ext:without-package-locks (setf (symbol-function 'close) original))
          (release-file-lock lock)))))
  (it "finds an external shared owner while a local shared lock is held"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "shared.lock" scratch))
             (ready (merge-pathnames "shared-ready" scratch))
             (holder nil)
             (form (format nil
                           "(with-open-file (stream ~S :direction :io :if-exists :overwrite) (sb-posix:fcntl (sb-sys:fd-stream-fd stream) sb-posix:f-setlk (make-instance 'sb-posix:flock :type sb-posix:f-rdlck :whence sb-posix:seek-set :start 0 :len 0)) (with-open-file (output ~S :direction :output :if-exists :supersede) (write-line \"ready\" output)) (sleep 30))"
                           (namestring target) (namestring ready))))
        (write-file-string "" target)
        (unwind-protect
             (with-open-file (stream target :direction :io :if-exists :overwrite)
               (with-advisory-file-lock (stream :mode :shared)
                 (setf holder (sb-ext:run-program
                               (namestring sb-ext:*runtime-pathname*)
                               (list "--noinform" "--non-interactive"
                                     "--eval" "(require :sb-posix)" "--eval" form)
                               :wait nil :output nil :error nil))
                 (%wait-for-lock-holder ready)
                 (expect (file-lock-held-by-other-process-p target) :to-be t)))
          (when holder
            (sb-ext:process-kill holder 15)
            (sb-ext:process-wait holder)))))))


(describe "retained file lock operational failures"
  (it "preserves a flush failure while unlocking and closing after a second failure"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "flush-error.lock" scratch))
             (lock (try-acquire-file-lock target))
             (stream (file-lock-stream lock))
             (flush (symbol-function 'finish-output))
             (unlock (symbol-function 'host-kit::%release-advisory-file-lock))
             (first (make-condition 'simple-error :format-control "flush failure")))
        (unwind-protect
             (progn
               (sb-ext:without-package-locks
                 (setf (symbol-function 'finish-output)
                       (lambda (&optional candidate)
                         (if (eq candidate stream)
                             (error first)
                             (funcall flush candidate)))))
               (setf (symbol-function 'host-kit::%release-advisory-file-lock)
                     (lambda (fd start)
                       (funcall unlock fd start)
                       (error "unlock failure")))
               (expect (handler-case (release-file-lock lock)
                         (host-operation-failed (condition)
                           (host-operation-failed-reason condition)))
                       :to-be first)
               (expect (open-stream-p stream) :to-be nil)
               (expect (release-file-lock lock) :to-be nil)
               (expect (%child-lock-exit-code target) :to-equal 0))
          (sb-ext:without-package-locks (setf (symbol-function 'finish-output) flush))
          (setf (symbol-function 'host-kit::%release-advisory-file-lock) unlock)
          (release-file-lock lock)))))
  (it "reports non-conflict acquisition failures and permits a subsequent acquisition"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "acquire-error.lock" scratch))
             (original (symbol-function 'host-kit::%acquire-advisory-file-lock)))
        (unwind-protect
             (progn
               (setf (symbol-function 'host-kit::%acquire-advisory-file-lock)
                     (lambda (&rest arguments)
                       (declare (ignore arguments))
                       (sb-posix:fcntl -1 sb-posix:f-getfd)))
               (signals host-operation-failed (try-acquire-file-lock target)))
          (setf (symbol-function 'host-kit::%acquire-advisory-file-lock) original))
        (let ((lock (try-acquire-file-lock target)))
          (expect (typep lock 'file-lock) :to-be t)
          (release-file-lock lock)))))
  (it "reports a non-directory path component instead of an unlocked result"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "regular" scratch))
            (target (merge-pathnames "regular/child.lock" scratch)))
        (write-file-string "contents" file)
        (signals host-operation-failed (file-lock-held-by-other-process-p target))
        (signals host-operation-failed (try-acquire-file-lock target))))))


(defun %lock-test-wait (semaphore)
  (unless (sb-thread:wait-on-semaphore semaphore :timeout 2)
    (error "Lock test synchronization did not complete.")))

(defun %lock-retirement-handoff (target owned-pathname-p)
  (with-open-file (first target :direction :io :if-exists :overwrite)
    (with-open-file (second target :direction :io :if-exists :overwrite)
      (let ((first-body (sb-thread:make-semaphore :count 0))
            (return-first (sb-thread:make-semaphore :count 0))
            (retiring (sb-thread:make-semaphore :count 0))
            (finish-retiring (sb-thread:make-semaphore :count 0))
            (second-attempted (sb-thread:make-semaphore :count 0))
            (second-acquired (sb-thread:make-semaphore :count 0))
            (return-second (sb-thread:make-semaphore :count 0))
            (original (symbol-function 'host-kit::%release-advisory-file-lock))
            (old-thread nil) (new-thread nil)
            (old-error nil) (new-error nil)
            (protected nil) (new-live nil))
        (labels ((old-body (stream)
                   (declare (ignore stream))
                   (sb-thread:signal-semaphore first-body)
                   (%lock-test-wait return-first))
                 (new-body (stream)
                   (declare (ignore stream))
                   (setf new-live t)
                   (sb-thread:signal-semaphore second-acquired)
                   (unwind-protect (%lock-test-wait return-second)
                     (setf new-live nil))))
          (unwind-protect
               (progn
                 (setf (symbol-function 'host-kit::%release-advisory-file-lock)
                       (lambda (fd start)
                         (if (eq sb-thread:*current-thread* old-thread)
                             (progn
                               (when owned-pathname-p (funcall original fd start))
                               (setf protected
                                     (sb-thread:holding-mutex-p host-kit::*advisory-file-locks-lock*))
                               (sb-thread:signal-semaphore retiring)
                               (%lock-test-wait finish-retiring)
                               (unless owned-pathname-p (funcall original fd start)))
                             (funcall original fd start))))
                 (setf old-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (if owned-pathname-p
                                  (call-with-file-lock #'old-body target)
                                  (call-with-advisory-file-lock #'old-body first))
                            (error (condition) (setf old-error condition))))))
                 (%lock-test-wait first-body)
                 (sb-thread:signal-semaphore return-first)
                 (%lock-test-wait retiring)
                 (setf new-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (sb-thread:signal-semaphore second-attempted)
                          (handler-case
                              (if owned-pathname-p
                                  (let ((lock (try-acquire-file-lock target)))
                                    (unwind-protect (new-body (file-lock-stream lock))
                                      (release-file-lock lock)))
                                  (call-with-advisory-file-lock #'new-body second :wait nil))
                            (error (condition)
                              (setf new-error condition)
                              (sb-thread:signal-semaphore second-acquired))))))
                 (%lock-test-wait second-attempted)
                 ;; The protected implementation releases the mutex before the
                 ;; next owner can enter. The old implementation admits it here.
                 (when protected (sb-thread:signal-semaphore finish-retiring))
                 (%lock-test-wait second-acquired)
                 (let ((before (%child-lock-exit-code target)))
                   (unless protected (sb-thread:signal-semaphore finish-retiring))
                   (sb-thread:join-thread old-thread :timeout 2)
                   (list (not (null protected)) before new-live
                         (%child-lock-exit-code target)
                         (null old-error) (null new-error))))
            (setf (symbol-function 'host-kit::%release-advisory-file-lock) original)
            (sb-thread:signal-semaphore return-first)
            (sb-thread:signal-semaphore finish-retiring)
            (sb-thread:signal-semaphore return-second)
            (dolist (thread (list old-thread new-thread))
              (when thread (sb-thread:join-thread thread :timeout 2)))))))))

(cl-weave:describe-sequential "retained and scoped lock interoperability"
  (it "rejects a pathname scope before opening a descriptor for a retained inode"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "mixed.lock" scratch))
             (lock (try-acquire-file-lock target)))
        (unwind-protect
             (progn
               (signals host-operation-failed
                 (call-with-file-lock #'identity target :wait nil))
               (expect (%child-lock-exit-code target) :to-equal 1))
          (release-file-lock lock)))))
  (it-each ((:pathname) (:stream))
      "rejects the default waiting ~S scope instead of waiting on its retained lock"
      (kind)
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "default-wait.lock" scratch))
             (lock (try-acquire-file-lock target))
             (attempted (sb-thread:make-semaphore :count 0))
             (worker nil))
        (unwind-protect
             (progn
               (setf worker
                     (sb-thread:make-thread
                      (lambda ()
                        (sb-thread:signal-semaphore attempted)
                        (handler-case
                            (if (eq kind :pathname)
                                (call-with-file-lock #'identity target)
                                (call-with-advisory-file-lock #'identity (file-lock-stream lock)))
                          (host-operation-failed () :rejected)))))
               (%lock-test-wait attempted)
               (expect (sb-thread:join-thread worker :timeout 1 :default :blocked)
                       :to-equal :rejected))
          (when (and worker (sb-thread:thread-alive-p worker))
            (sb-thread:terminate-thread worker)
            (sb-thread:join-thread worker :default nil :timeout 2))
          (release-file-lock lock)))))
  (it "keeps its owned stream alive after the file-lock reference is discarded"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "owned.lock" scratch))
            (reservation nil))
        (multiple-value-bind (weak-lock weak-stream)
            (sb-thread:join-thread
             (sb-thread:make-thread (lambda () (%retained-lock-weak-references target))) :timeout 2)
          (unwind-protect
               (progn
                 (sb-ext:gc :full t)
                 (setf reservation (host-kit::%held-file-lock-for-path target))
                 (expect (sb-ext:weak-pointer-value weak-lock) :to-be nil)
                 (expect (open-stream-p (sb-ext:weak-pointer-value weak-stream)) :to-be t)
                 (expect (host-kit::%held-advisory-file-lock-stream reservation)
                         :to-be (sb-ext:weak-pointer-value weak-stream))
                 (expect (%child-lock-exit-code target) :to-equal 1))
            (when reservation
              (release-file-lock
               (host-kit::%make-file-lock
                (host-kit::%held-advisory-file-lock-stream reservation) reservation)))))
        (expect (host-kit::%held-advisory-file-lock-stream reservation) :to-be nil)
        (expect (%child-lock-exit-code target) :to-equal 0))))
  (it "keeps the next supplied-stream owner locked after the old scope retires"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "supplied-handoff.lock" scratch)))
        (write-file-string "" target)
        (expect (%lock-retirement-handoff target nil) :to-equal '(t 1 t 1 t t)))))
  (it "closes an owned pathname descriptor before another retained owner enters"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "owned-handoff.lock" scratch)))
        (write-file-string "" target)
        (expect (%lock-retirement-handoff target t) :to-equal '(t 1 t 1 t t)))))
  (it "unlocks when the last shared owner outlives the creating scope"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "shared-retirement.lock" scratch)))
        (write-file-string "" target)
        (with-open-file (first target :direction :io :if-exists :overwrite)
          (with-open-file (second target :direction :io :if-exists :overwrite)
            (let ((first-ready (sb-thread:make-semaphore :count 0))
                  (second-ready (sb-thread:make-semaphore :count 0))
                  (return-first (sb-thread:make-semaphore :count 0))
                  (return-second (sb-thread:make-semaphore :count 0))
                  (old-thread nil) (new-thread nil))
              (unwind-protect
                   (progn
                     (setf old-thread
                           (sb-thread:make-thread
                            (lambda ()
                              (call-with-advisory-file-lock
                               (lambda (stream)
                                 (declare (ignore stream))
                                 (sb-thread:signal-semaphore first-ready)
                                 (%lock-test-wait return-first))
                               first :mode :shared))))
                     (%lock-test-wait first-ready)
                     (setf new-thread
                           (sb-thread:make-thread
                            (lambda ()
                              (call-with-advisory-file-lock
                               (lambda (stream)
                                 (declare (ignore stream))
                                 (sb-thread:signal-semaphore second-ready)
                                 (%lock-test-wait return-second))
                               second :mode :shared))))
                     (%lock-test-wait second-ready)
                     (expect (%child-lock-exit-code target) :to-equal 1)
                     (sb-thread:signal-semaphore return-first)
                     (sb-thread:join-thread old-thread :timeout 2)
                     (expect (%child-lock-exit-code target) :to-equal 1)
                     (sb-thread:signal-semaphore return-second)
                     (sb-thread:join-thread new-thread :timeout 2)
                     (expect (%child-lock-exit-code target) :to-equal 0))
                (sb-thread:signal-semaphore return-first)
                (sb-thread:signal-semaphore return-second)
                (dolist (thread (list old-thread new-thread))
                  (when thread (sb-thread:join-thread thread :timeout 2)))))))))))


(defun %retained-lock-weak-references (target)
  (let ((lock (try-acquire-file-lock target)))
    (values (sb-ext:make-weak-pointer lock)
            (sb-ext:make-weak-pointer (file-lock-stream lock)))))

(defun %owned-shared-scope-outcome (target creator-abort-p borrower-abort-p)
  (with-open-file (borrowed target :direction :io :if-exists :overwrite)
    (let ((ready (sb-thread:make-semaphore :count 0))
          (finish (sb-thread:make-semaphore :count 0))
          (worker nil) (owned nil) (creator-error nil) (borrower-error nil)
          (creator-condition (make-condition 'simple-error :format-control "creator failed"))
          (borrower-condition (make-condition 'simple-error :format-control "borrower failed")))
      (unwind-protect
           (progn
             (handler-case
                 (call-with-file-lock
                  (lambda (stream)
                    (setf owned stream)
                    (write-string "changed!" stream)
                    (setf worker
                          (sb-thread:make-thread
                           (lambda ()
                             (handler-case
                                 (call-with-advisory-file-lock
                                  (lambda (other)
                                    (declare (ignore other))
                                    (sb-thread:signal-semaphore ready)
                                    (%lock-test-wait finish)
                                    (when borrower-abort-p (error borrower-condition)))
                                  borrowed :mode :shared)
                               (host-operation-failed (condition)
                                 (setf borrower-error (host-operation-failed-reason condition)))))))
                    (%lock-test-wait ready)
                    (when creator-abort-p (error creator-condition)))
                  target :mode :shared)
               (host-operation-failed (condition)
                 (setf creator-error (host-operation-failed-reason condition))))
             (expect (open-stream-p owned) :to-be t)
             (expect (%child-lock-exit-code target) :to-equal 1)
             (sb-thread:signal-semaphore finish)
             (sb-thread:join-thread worker :timeout 2)
             (expect (open-stream-p owned) :to-be nil)
             (expect (%child-lock-exit-code target) :to-equal 0)
             (expect creator-error :to-be (and creator-abort-p creator-condition))
             (expect borrower-error :to-be (and borrower-abort-p borrower-condition))
             ;; The caller's descriptor remains open until these observations end.
             (expect (read-line borrowed) :to-equal
                     (if creator-abort-p "original" "changed!")))
        (sb-thread:signal-semaphore finish)
        (when worker (sb-thread:join-thread worker :timeout 2))))))

(cl-weave:describe-sequential "pathname scoped lock compatibility"
  (it "waits for another thread's pathname scope before opening and acquiring"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "waiting.lock" scratch))
            (attempted (sb-thread:make-semaphore :count 0))
            (worker nil))
        (unwind-protect
             (progn
               (call-with-file-lock
                (lambda (stream)
                  (declare (ignore stream))
                  (setf worker
                        (sb-thread:make-thread
                         (lambda ()
                           (sb-thread:signal-semaphore attempted)
                           (handler-case
                               (call-with-file-lock (lambda (other) (declare (ignore other)) :acquired)
                                                    target :wait t)
                             (host-operation-failed () :rejected)))))
                  (%lock-test-wait attempted)
                  (expect (sb-thread:join-thread worker :timeout 0.05 :default :waiting)
                          :to-equal :waiting)
                  (expect (%child-lock-exit-code target) :to-equal 1))
                target)
               (expect (sb-thread:join-thread worker :timeout 2 :default :blocked)
                       :to-equal :acquired))
          (when worker
            (when (sb-thread:thread-alive-p worker)
              (sb-thread:terminate-thread worker))
            (sb-thread:join-thread worker :timeout 2 :default nil))))))
  (it-each ((nil nil :rejected) (t 0.05 :timed-out))
      "keeps the current owner's OS lock after wait ~S timeout ~S rejection"
      (wait timeout expected)
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "rejection.lock" scratch)))
        (call-with-file-lock
         (lambda (stream)
           (declare (ignore stream))
           (let ((worker
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (call-with-file-lock #'identity target :wait wait :timeout timeout)
                        (file-lock-timeout (condition)
                          (values :timed-out (file-lock-timeout-seconds condition)))
                        (host-operation-failed () :rejected))))))
             (multiple-value-bind (outcome seconds)
                 (sb-thread:join-thread worker :timeout 2 :default :blocked)
               (expect outcome :to-equal expected)
               (when timeout (expect seconds :to-equal timeout)))
             (expect (%child-lock-exit-code target) :to-equal 1)))
         target))))
  (it "rejects a same-thread pathname scope without releasing the enclosing lock"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "nested-owned.lock" scratch)))
        (call-with-file-lock
         (lambda (stream)
           (declare (ignore stream))
           (signals host-operation-failed (call-with-file-lock #'identity target))
           (expect (%child-lock-exit-code target) :to-equal 1))
         target))))
  (it-each ((nil nil) (t nil) (nil t))
      "defers owned shared cleanup with creator-abort ~S borrower-abort ~S"
      (creator-abort-p borrower-abort-p)
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "owned-shared.lock" scratch)))
        (write-file-string "original" target)
        (%owned-shared-scope-outcome target creator-abort-p borrower-abort-p))))
  (it "discards abnormal buffered output and preserves the original callback failure"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "abort-error.lock" scratch))
             (original (symbol-function 'host-kit::%release-advisory-file-lock))
             (primary (make-condition 'simple-error :format-control "callback failed"))
             (secondary (make-condition 'simple-error :format-control "unlock cleanup failed"))
             (observed nil) (owned nil))
        (write-file-string "original" target)
        (with-function-redefinition
            ('host-kit::%release-advisory-file-lock
             (lambda (fd start) (funcall original fd start) (error secondary)))
          (handler-case
              (call-with-file-lock
               (lambda (stream)
                 (setf owned stream)
                 (write-string "changed!" stream)
                 (error primary))
               target)
            (host-operation-failed (condition)
              (setf observed (host-operation-failed-reason condition)))))
        (expect observed :to-be primary)
        (expect (read-file-string target) :to-equal "original")
        (expect (open-stream-p owned) :to-be nil)
        (expect (%child-lock-exit-code target) :to-equal 0))))
  (it "discards abnormal buffered output after a nonlocal exit"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "abort-throw.lock" scratch)))
        (write-file-string "original" target)
        (expect (catch 'abort-scope
                  (call-with-file-lock
                   (lambda (stream)
                     (write-string "changed!" stream)
                     (throw 'abort-scope :aborted))
                   target))
                :to-equal :aborted)
        (expect (read-file-string target) :to-equal "original")
        (expect (%child-lock-exit-code target) :to-equal 0)))))


(cl-weave:describe-sequential "pathname scoped lock compatibility cleanup"
  (it "preserves a shared borrower's callback failure after final cleanup fails"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "borrower-cleanup.lock" scratch))
             (original (symbol-function 'host-kit::%release-advisory-file-lock)))
        (write-file-string "original" target)
        (with-function-redefinition
            ('host-kit::%release-advisory-file-lock
             (lambda (fd start)
               (funcall original fd start)
               (error "final cleanup failed")))
          (%owned-shared-scope-outcome target nil t))))))


(cl-weave:describe-sequential "native lock paths and normal cleanup failures"
  (it "locks the literal native b*c.lock inode without opening an escaped neighbor"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames (sb-ext:parse-native-namestring "b*c.lock") scratch))
             (lock nil))
        (with-open-file (stream target :direction :output :if-exists :supersede)
          (write-string "metadata" stream))
        (unwind-protect
             (progn
               (setf lock (try-acquire-file-lock target))
               (expect (%child-lock-exit-code target) :to-equal 1)
               (expect (file-lock-held-by-other-process-p target) :to-be nil)
               (expect (%child-lock-exit-code target) :to-equal 1)
               (signals host-operation-failed (try-acquire-file-lock target))
               (expect (%child-lock-exit-code target) :to-equal 1))
          (when lock (release-file-lock lock)))
        (expect (%child-lock-exit-code target) :to-equal 0))))
  (it "reports unlock failure after a normal acquired callback and closes its owned stream"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "normal-acquired.lock" scratch))
             (original (symbol-function 'host-kit::%release-advisory-file-lock))
             (failure (make-condition 'simple-error :format-control "unlock failed"))
             (returned nil) (owned nil) (observed nil))
        (with-function-redefinition
            ('host-kit::%release-advisory-file-lock
             (lambda (fd start) (funcall original fd start) (error failure)))
          (handler-case
              (call-with-file-lock
               (lambda (stream) (setf owned stream returned t) :normal)
               target)
            (host-operation-failed (condition)
              (setf observed (host-operation-failed-reason condition)))))
        (expect returned :to-be t)
        (expect observed :to-be failure)
        (expect (open-stream-p owned) :to-be nil)
        (expect (host-kit::%held-file-lock-for-path target) :to-be nil)
        (expect (%child-lock-exit-code target) :to-equal 0))))
  (it "reports unlock failure to a normal last shared borrower after retiring the owned stream"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "normal-shared.lock" scratch))
             (original (symbol-function 'host-kit::%release-advisory-file-lock))
             (failure (make-condition 'simple-error :format-control "shared unlock failed"))
             (ready (sb-thread:make-semaphore :count 0))
             (finish (sb-thread:make-semaphore :count 0))
             (worker nil) (owned nil) (returned nil))
        (write-file-string "metadata" target)
        (with-open-file (borrowed target :direction :io :if-exists :overwrite)
          (unwind-protect
               (with-function-redefinition
                   ('host-kit::%release-advisory-file-lock
                    (lambda (fd start) (funcall original fd start) (error failure)))
                 (call-with-file-lock
                  (lambda (stream)
                    (setf owned stream)
                    (setf worker
                          (sb-thread:make-thread
                           (lambda ()
                             (handler-case
                                 (call-with-advisory-file-lock
                                  (lambda (other)
                                    (declare (ignore other))
                                    (sb-thread:signal-semaphore ready)
                                    (%lock-test-wait finish)
                                    (setf returned t)
                                    :normal)
                                  borrowed :mode :shared)
                               (host-operation-failed (condition)
                                 (host-operation-failed-reason condition))))))
                    (%lock-test-wait ready))
                  target :mode :shared)
                 (sb-thread:signal-semaphore finish)
                 (expect (sb-thread:join-thread worker :timeout 2 :default :blocked)
                         :to-be failure)
                 (expect returned :to-be t)
                 (expect (open-stream-p owned) :to-be nil)
                 (expect (open-stream-p borrowed) :to-be t)
                 (expect (host-kit::%held-file-lock-for-path target) :to-be nil)
                 (expect (%child-lock-exit-code target) :to-equal 0))
            (sb-thread:signal-semaphore finish)
            (when worker
              (when (sb-thread:thread-alive-p worker)
                (sb-thread:terminate-thread worker))
              (sb-thread:join-thread worker :timeout 2 :default nil))))))))




