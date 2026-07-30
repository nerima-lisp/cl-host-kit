;;;; src/file-locking.lisp
;;;;
;;;; Scoped, cooperative POSIX file locking for SBCL file-descriptor streams.
(in-package #:host-kit)

(defun %advisory-file-lock-fd (stream)
  (check-type stream sb-sys:fd-stream)
  (unless (open-stream-p stream)
    (error 'type-error :datum stream :expected-type 'open-stream))
    (sb-sys:fd-stream-fd stream))

(defstruct (%held-advisory-file-lock
            (:constructor %make-held-advisory-file-lock))
  identity
  fd
  lock-start
  mode
  owners)

(defvar *held-advisory-file-locks* nil
  "Process-wide file locks reserved by active HOST-KIT lock scopes.")

(defvar *advisory-file-locks-lock*
  (sb-thread:make-mutex :name "host-kit advisory file locks"))

(defun %advisory-file-lock-identity (fd)
  "Return the stable filesystem identity associated with FD."
  (let ((stat (sb-posix:fstat fd)))
    (cons (sb-posix:stat-dev stat)
          (sb-posix:stat-ino stat))))

(defun %conflicting-file-lock-p (condition)
  (member (sb-posix:syscall-errno condition)
          (list sb-posix:eacces sb-posix:eagain)))

(progn
  (defun %advisory-file-lock-deadline (timeout)
    (and timeout
         (+ (get-internal-real-time)
            (ceiling (* timeout internal-time-units-per-second)))))

  (defun %find-held-advisory-file-lock (identity)
    (find identity *held-advisory-file-locks*
          :key (function %held-advisory-file-lock-identity)
          :test (function equal)))

  (defun %advisory-file-lock-reservation-status
      (identity fd lock-start mode wait deadline)
    (let ((owner sb-thread:*current-thread*))
      (sb-thread:with-mutex (*advisory-file-locks-lock*)
        (let ((held-lock (%find-held-advisory-file-lock identity)))
          (cond
            ((null held-lock)
             (let ((new-lock
                     (%make-held-advisory-file-lock
                      :identity identity :fd fd :lock-start lock-start
                      :mode mode :owners (list owner))))
               (push new-lock *held-advisory-file-locks*)
               (values :acquired new-lock)))
            ((and (member owner (%held-advisory-file-lock-owners held-lock)
                          :test (function eq))
                  (= fd (%held-advisory-file-lock-fd held-lock)))
             (values :nested held-lock))
            ((and (eq mode :shared)
                  (eq (%held-advisory-file-lock-mode held-lock) :shared))
             (push owner (%held-advisory-file-lock-owners held-lock))
             (values :shared held-lock))
            ((member owner (%held-advisory-file-lock-owners held-lock)
                     :test (function eq))
             (values :different-stream held-lock))
            ((not wait)
             (values :unavailable held-lock))
            ((and deadline
                  (>= (get-internal-real-time) deadline))
             (values :timed-out held-lock))
            (t
             (values :wait held-lock)))))))

  (defun %reserve-advisory-file-lock (identity fd lock-start mode wait timeout)
    "Reserve IDENTITY for this thread and return its acquisition status."
    (let ((deadline (%advisory-file-lock-deadline timeout)))
      (loop
        (multiple-value-bind (outcome held-lock)
            (%advisory-file-lock-reservation-status
             identity fd lock-start mode wait deadline)
          (case outcome
            ((:acquired :nested :shared)
             (return (values outcome deadline held-lock)))
            (:different-stream
             (error "Nested advisory locks for one file must use the original stream."))
            (:unavailable
             (error "An advisory lock for this file is already held in this process."))
            (:timed-out
             (error (quote file-lock-timeout) :seconds timeout))
            (:wait
             (sleep 0.01d0))))))))

(defun %release-advisory-file-lock-reservation (identity fd)
  (let ((owner sb-thread:*current-thread*))
    (sb-thread:with-mutex (*advisory-file-locks-lock*)
      (let ((held-lock
              (find identity *held-advisory-file-locks*
                    :key #'%held-advisory-file-lock-identity
                    :test #'equal)))
    (when (and held-lock
               (or (= fd (%held-advisory-file-lock-fd held-lock))
                   (eq (%held-advisory-file-lock-mode held-lock) :shared)))
          (setf (%held-advisory-file-lock-owners held-lock)
                (delete owner (%held-advisory-file-lock-owners held-lock)
                        :test #'eq :count 1))
          (unless (%held-advisory-file-lock-owners held-lock)
            (setf *held-advisory-file-locks*
                  (delete held-lock *held-advisory-file-locks*))
            t))))))

(defun %remaining-advisory-file-lock-timeout (deadline)
  (and deadline
       (max 0d0
            (/ (- deadline (get-internal-real-time))
               internal-time-units-per-second))))

(defun %make-advisory-file-lock (mode lock-start)
  (make-instance 'sb-posix:flock
                 :type (ecase mode
                         (:exclusive sb-posix:f-wrlck)
                         (:shared sb-posix:f-rdlck))
                 :whence sb-posix:seek-set
                 :start lock-start
                 :len 0))

(defun %acquire-advisory-file-lock (fd wait timeout
                                    &optional reported-timeout
                                      (mode :exclusive)
                                      (lock-start 0))
  (let ((lock (%make-advisory-file-lock mode lock-start)))
    (cond
      ((not wait)
       (sb-posix:fcntl fd sb-posix:f-setlk lock))
      ((null timeout)
       (sb-posix:fcntl fd sb-posix:f-setlkw lock))
      (t
       (let ((deadline (+ (get-internal-real-time)
                          (ceiling (* timeout internal-time-units-per-second)))))
         (loop
           (handler-case
               (return (sb-posix:fcntl fd sb-posix:f-setlk lock))
             (sb-posix:syscall-error (condition)
               (unless (%conflicting-file-lock-p condition)
                 (error condition))))
           (when (>= (get-internal-real-time) deadline)
             (error 'file-lock-timeout :seconds (or reported-timeout timeout)))
           (sleep 0.01d0)))))))

(defun %release-advisory-file-lock (fd lock-start)
  (sb-posix:fcntl fd sb-posix:f-setlk
                  (make-instance 'sb-posix:flock
                                 :type sb-posix:f-unlck
                                 :whence sb-posix:seek-set
                                 :start lock-start
                                 :len 0)))

(progn
  (defun %call-with-shared-advisory-file-lock (thunk stream identity fd)
    (unwind-protect
         (funcall thunk stream)
      (%release-advisory-file-lock-reservation identity fd)))

  (defun %call-with-acquired-advisory-file-lock
      (thunk stream identity fd lock-start wait deadline timeout mode held-lock)
    (let ((lock-acquired-p nil))
      (unwind-protect
           (progn
             (%acquire-advisory-file-lock
              fd wait (%remaining-advisory-file-lock-timeout deadline)
              timeout mode lock-start)
             (setf lock-acquired-p t)
             (funcall thunk stream))
        (when (and (%release-advisory-file-lock-reservation identity fd) lock-acquired-p) (%release-advisory-file-lock
                  (%held-advisory-file-lock-fd held-lock)
                  (%held-advisory-file-lock-lock-start held-lock))))))

  (defun %call-with-reserved-advisory-file-lock
      (thunk stream identity fd lock-start mode wait timeout status deadline held-lock)
    (ecase status
      (:nested
       (funcall thunk stream))
      (:shared
       (%call-with-shared-advisory-file-lock thunk stream identity fd))
      (:acquired
       (%call-with-acquired-advisory-file-lock
        thunk stream identity fd lock-start wait deadline timeout mode held-lock))))

  (defun call-with-advisory-file-lock (thunk stream
                                       &key (wait t) timeout (mode :exclusive))
    "Call THUNK while holding a MODE advisory lock on STREAM.

MODE is :EXCLUSIVE (the default) or :SHARED. Shared locks coexist only with
other shared locks; exclusive locks conflict with both modes. The lock covers
the byte range from STREAM's current position through EOF.
When WAIT is true, wait for a conflicting cooperative lock to be released;
otherwise signal HOST-OPERATION-FAILED immediately when it cannot be
acquired.  With a non-NIL TIMEOUT, wait at most that many seconds and signal
FILE-LOCK-TIMEOUT on expiry. STREAM must be an open SBCL file-descriptor
stream. All values returned by THUNK are preserved, and the lock is released
on every exit path."
    (check-type thunk function)
    (check-type wait boolean)
    (check-type timeout (or null (real 0 *)))
    (check-type mode (member :exclusive :shared))
    (let ((fd (%advisory-file-lock-fd stream)))
      (%with-host-operation (:call-with-advisory-file-lock nil)
        (let ((identity (%advisory-file-lock-identity fd))
              (lock-start (file-position stream)))
          ;; POSIX record locks belong to the process, so track ownership across
          ;; threads before acquiring the OS lock. Otherwise one thread can
          ;; silently release another scope's lock on the same file.
          (multiple-value-bind (status deadline held-lock)
              (%reserve-advisory-file-lock identity fd lock-start mode wait timeout)
            (%call-with-reserved-advisory-file-lock
             thunk stream identity fd lock-start mode wait timeout
             status deadline held-lock)))))))
(progn
  (defmacro with-advisory-file-lock ((stream &key (wait t) timeout (mode :exclusive))
                                     &body body)
    "Evaluate BODY while holding a MODE advisory lock on STREAM.

TIMEOUT has the same bounded-wait semantics as CALL-WITH-ADVISORY-FILE-LOCK.
STREAM names an already-open stream, reused (not newly introduced) as BODY's
binding, so this scope does not fit DEFINE-WITH-MACRO's fresh-binding shape."
    (%validate-bound-variables (list stream))
    `(call-with-advisory-file-lock
      (lambda (,stream)
        ,@body)
      ,stream
      :wait ,wait
      :timeout ,timeout
      :mode ,mode))

  (defun call-with-file-lock (thunk pathspec
                              &key (wait t) timeout (mode :exclusive))
    "Call THUNK while holding a MODE advisory lock for PATHSPEC.

PATHSPEC is opened for non-destructive I/O, creating an absent regular file.
The lock covers the byte range from zero through EOF. THUNK receives the open
stream, and its values are preserved. The lock is released and the stream is
closed on every exit path. Each call owns a descriptor, so use
CALL-WITH-ADVISORY-FILE-LOCK with a supplied stream for nested locking."
    (check-type thunk function)
    (check-type wait boolean)
    (check-type timeout (or null (real 0 *)))
    (check-type mode (member :exclusive :shared))
    (let ((pathname (ensure-absolute-pathname pathspec)))
      (%with-host-operation (:call-with-file-lock pathname)
        (with-open-file (stream pathname
                                :direction :io
                                :if-does-not-exist :create
                                :if-exists :overwrite)
          (call-with-advisory-file-lock thunk stream
                                        :wait wait
                                        :timeout timeout
                                        :mode mode)))))

  (define-with-macro with-file-lock (stream) call-with-file-lock))

