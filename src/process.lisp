;;;; src/process.lisp
;;;;
;;;; A small direct SBCL process API. It accepts an argv list rather than
;;;; shell text, and drains both output pipes concurrently.
(in-package #:host-kit)

(defconstant +default-command-timeout-seconds+ 30d0
  "Default wall-clock timeout used by RUN-PROGRAM.")

(defconstant +default-command-output-limit+ (* 1024 1024))

(defstruct process-result "Terminal data captured by RUN-PROGRAM. A non-zero EXIT-CODE is data, not
an error; TIMEOUT is reported separately by PROCESS-TIMEOUT."
  program
  arguments
  exit-code
  signal
  (stdout "" :type string)
  (stderr "" :type string)
  timed-out-p
  stdout-truncated-p
  stderr-truncated-p)

(defun %validate-expected-exit-codes (expected-exit-codes)
  (check-type expected-exit-codes list)
  (let ((exit-code-count (list-length expected-exit-codes)))
    (unless (and exit-code-count (plusp exit-code-count))
      (error
        (quote type-error)
        :datum
        expected-exit-codes
        :expected-type
        (quote list))))
  (dolist (exit-code expected-exit-codes)
    (check-type exit-code (integer 0 *)))
  expected-exit-codes)

(defun ensure-program-success (result &key (expected-exit-codes '(0)))
  "Return RESULT when its exit code is expected, otherwise signal PROCESS-EXIT-ERROR.
EXPECTED-EXIT-CODES is a list of non-negative integer exit codes."
  (check-type result process-result)
  (%validate-expected-exit-codes expected-exit-codes)
  (unless (member (process-result-exit-code result) expected-exit-codes :test #'eql)
    (error
      'process-exit-error
      :program
      (process-result-program result)
      :arguments
      (process-result-arguments result)
      :exit-code
      (process-result-exit-code result)
      :signal
      (process-result-signal result)
      :expected-exit-codes
      expected-exit-codes
      :result
      result))
  result)

#+sbcl
(defun find-program (program &key (path (getenv "PATH")))
  "Return the executable pathname for PROGRAM, or NIL when none is found.
PROGRAM may be an explicit path or a bare file name. Bare names are searched
through the colon-separated PATH string; an empty PATH element denotes the
current directory."
  (check-type program string)
  (check-type path (or null string))
  (cond
    ((find #\/ program)
     (file-executable-p program))
    ((null path) nil)
    (t
     (loop for directory in (split-string path :separator #\:)
           for candidate = (merge-pathnames program
                                            (if (string= directory "")
                                                (ensure-directory-pathname
                                                 (sb-posix:getcwd))
                                                (ensure-directory-pathname directory)))
           for executable = (file-executable-p candidate)
           when executable return executable))))

#-sbcl
(defun find-program (program &rest keys)
  (declare (ignore program keys))
  (%unsupported 'find-program))

#+sbcl
(progn
  (eval-when (:compile-toplevel :load-toplevel :execute)
    (require :sb-posix))

  (defstruct (%output-capture (:constructor %make-output-capture))
    stream
    owner
    thread
    (truncated-p nil)
    (abandoned-p nil)
    (stop-requested-p nil)
    condition)

  (defvar *active-output-captures* nil)
  (defvar *active-output-captures-lock*
    (sb-thread:make-mutex :name "cl-host-kit active output captures"))

  (defun %register-output-capture (capture)
    (sb-thread:with-mutex (*active-output-captures-lock*)
      (push capture *active-output-captures*))
    capture)

  (defun %unregister-output-capture (capture)
    (sb-thread:with-mutex (*active-output-captures-lock*)
      (setf *active-output-captures*
            (delete capture *active-output-captures* :test (function eq)))))

  (defun %record-output-capture-condition (capture condition)
    (sb-thread:with-mutex (*active-output-captures-lock*)
      (setf (%output-capture-condition capture) condition)))

  (defun %output-capture-failed-p (owner)
    (sb-thread:with-mutex (*active-output-captures-lock*)
      (some (lambda (capture)
              (and (eq (%output-capture-owner capture) owner)
                   (%output-capture-condition capture)))
            *active-output-captures*))))

#+sbcl
(defun %start-output-capture (stream limit name &optional consumer)
  (let ((sink (make-string-output-stream))
        (capture nil)
        (count 0)
        (fd (sb-sys:fd-stream-fd stream)))
    (labels ((capture-character ()
               (let ((character (read-char stream nil nil)))
                 (unless character
                   (return-from capture-character nil))
                 (if consumer (funcall consumer character)
                     (if (< count limit) (progn
                                          (write-char character sink)
                                          (incf count))
                         (setf (%output-capture-truncated-p capture) t)))
                 t)))
      (setf capture (%make-output-capture :stream stream :owner sb-thread:*current-thread*))
      (%register-output-capture capture)
      (setf (%output-capture-thread capture) (sb-thread:make-thread
          (lambda ()
            (handler-case (loop (cond
                                  ((listen stream)
                                   (unless (capture-character)
                                     (return)))
                                  ((%output-capture-stop-requested-p capture) (return))
                                  ((sb-sys:wait-until-fd-usable fd :input 0.02d0)
                                   (unless (capture-character)
                                     (return)))))
              (error (condition)
                (%record-output-capture-condition capture condition))))
          :name name))
      (values capture sink))))

#+sbcl
(defun %finish-output-capture (capture sink)
  (unwind-protect
       (let ((thread (%output-capture-thread capture)))
         ;; A descendant can retain this descriptor after its direct parent exits.
         (when (eq (sb-thread:join-thread thread
                                          :timeout 0.05d0
                                          :default :timed-out)
                   :timed-out)
           (setf (%output-capture-abandoned-p capture) t
                 (%output-capture-stop-requested-p capture) t)
           ;; The capture loop polls its descriptor, so this wait is bounded too.
           (sb-thread:join-thread thread :timeout 0.1d0 :default :timed-out))
         (ignore-errors (close (%output-capture-stream capture)))
         (let ((condition (%output-capture-condition capture)))
           (when (and condition (not (%output-capture-abandoned-p capture)))
             (error condition)))
         (get-output-stream-string sink))
    (%unregister-output-capture capture)))



(progn
  (defun %validate-proper-list (value)
    (unless (list-length value)
      (error (quote type-error) :datum value :expected-type (quote list)))
    value)

  (defun %validate-string-list-elements (values)
    (dolist (value values)
      (check-type value string))
    values)

  (defun %validate-string-list (values)
    (check-type values list)
    (%validate-proper-list values)
    (%validate-string-list-elements values))

  (defun %validate-program-environment (environment)
    (when environment
      (%validate-string-list environment)
      (dolist (entry environment)
        (let ((separator (position #\= entry)))
          (unless separator
            (error (quote type-error) :datum entry :expected-type (quote string)))
          (%check-environment-variable-name (subseq entry 0 separator))
          (%check-environment-variable-value (subseq entry (1+ separator))))))
    environment)

  (defun %validate-program-inputs
      (program arguments input timeout environment directory max-output-characters)
    (check-type program (or string pathname))
    (check-type arguments list)
    (%validate-proper-list arguments)
    (check-type input (or null string))
    (check-type timeout (real 0 *))
    (check-type directory (or null string pathname))
    (check-type max-output-characters (integer 0 *))
    (%validate-string-list-elements arguments)
    (%validate-program-environment environment)))

(progn
  (defun %normalize-program-directory (directory)
    "Return DIRECTORY as an absolute directory pathname, or NIL.
Relative child directories are resolved against the process CWD rather than
the implementation-dependent value of *DEFAULT-PATHNAME-DEFAULTS*."
    (when directory
      (ensure-directory-pathname
       (merge-pathnames (ensure-directory-pathname directory) (getcwd)))))
  #+sbcl
  (defun %process-terminal-p (process)
    (not (null (member (sb-ext:process-status process)
                       '(:exited :signaled))))))

(defun %wait-for-process (process timeout &key stop-when-output-fails-p)
  "Wait for PROCESS and report why the wait stopped.
Return :COMPLETED when PROCESS terminates, :OUTPUT-FAILED when an output
consumer failed and STOP-WHEN-OUTPUT-FAILS-P is true, or :TIMED-OUT."
  (let ((deadline (+ (get-internal-real-time)
                     ;; Do not expire a positive timeout before its requested duration.
                     (ceiling (* timeout internal-time-units-per-second)))))
    (loop until (%process-terminal-p process)
          when (and stop-when-output-fails-p
                    (%output-capture-failed-p sb-thread:*current-thread*))
            do (return :output-failed)
          when (>= (get-internal-real-time) deadline)
            do (return :timed-out)
          do (sleep 0.01d0)
          finally (return :completed))))

#+sbcl
(defun %process-termination-target (process)
  "Return the process-group target for PROCESS, or its PID as a safe fallback."
  (let ((pid (sb-ext:process-pid process)))
    ;; SBCL currently creates a separate process group for RUN-PROGRAM. Check
    ;; it before using a negative PID so a changed implementation cannot signal
    ;; the Lisp process's own group.
    (if (ignore-errors (= (sb-posix:getpgid pid) pid))
        (- pid)
        pid)))

(defun %terminate-process-group (process target)
  "Stop PROCESS's group at TARGET and ensure its direct child is reaped."
  (ignore-errors (sb-posix:kill target sb-posix:sigterm))
  (unless (eq (%wait-for-process process 1d0) :completed)
    (ignore-errors (sb-posix:kill target sb-posix:sigkill)))
  (sb-ext:process-wait process))

(defstruct (%input-producer (:constructor %make-input-producer)) stream
  thread
  condition)

(defun %start-input-producer (stream writer)
  (let ((producer (%make-input-producer :stream stream)))
    (setf (%input-producer-thread producer) (sb-thread:make-thread
        (lambda ()
          (unwind-protect (handler-case (funcall writer stream)
              (error (condition)
                (setf (%input-producer-condition producer) condition)))
            (ignore-errors (close stream))))
        :name
        "cl-host-kit program input"))
    producer))

(defun %finish-input-producer (producer &key (timeout 0.1d0))
  "Close PRODUCER input and wait at most TIMEOUT seconds for its worker.
The caller cannot safely terminate arbitrary Common Lisp code, so an input
callback that ignores its closed stream is detached after this bounded grace."
  (when producer
    (ignore-errors (close (%input-producer-stream producer)))
    (unless (eq
        (sb-thread:join-thread
          (%input-producer-thread producer)
          :timeout
          timeout
          :default
          :timed-out)
        :timed-out)
      (%input-producer-condition producer))))

(progn
  (defun %make-program-input-stream (input input-writer)
    (cond
      (input-writer :stream)
      (input (make-string-input-stream input))
      (t nil)))
  (defun %make-program-output-consumers (output-consumer)
    (if output-consumer (values
        (lambda (character)
          (funcall output-consumer :stdout character))
        (lambda (character)
          (funcall output-consumer :stderr character)))
      (values nil nil)))
  (defun %start-program-output-captures (process max-output-characters stdout-consumer stderr-consumer)
    (multiple-value-bind (stdout-capture stdout-sink) (%start-output-capture
        (sb-ext:process-output process)
        max-output-characters
        "cl-host-kit program stdout"
        stdout-consumer)
      (multiple-value-bind (stderr-capture stderr-sink) (%start-output-capture
          (sb-ext:process-error process)
          max-output-characters
          "cl-host-kit program stderr"
          stderr-consumer)
        (values stdout-capture stdout-sink stderr-capture stderr-sink))))
  (defun %make-program-result (program
      arguments
      process
      timeout
      wait-status
      input-producer
      stdout-capture
      stdout-sink
      stderr-capture
      stderr-sink)
    (let* ((timed-out-p (eq wait-status :timed-out))
           (input-condition (%finish-input-producer input-producer))
           (result
          (make-process-result
            :program
            program
            :arguments
            (copy-list arguments)
            :exit-code
            (and
              (eq (sb-ext:process-status process) :exited)
              (sb-ext:process-exit-code process))
            :signal
            (and
              (eq (sb-ext:process-status process) :signaled)
              (sb-ext:process-exit-code process))
            :stdout
            (%finish-output-capture stdout-capture stdout-sink)
            :stderr
            (%finish-output-capture stderr-capture stderr-sink)
            :timed-out-p
            timed-out-p
            :stdout-truncated-p
            (%output-capture-truncated-p stdout-capture)
            :stderr-truncated-p
            (%output-capture-truncated-p stderr-capture))))
      (when timed-out-p
        (error
          'process-timeout
          :program
          program
          :arguments
          arguments
          :seconds
          timeout
          :result
          result))
      (when input-condition
        (error input-condition))
      result))
  (defun %complete-program (program
      arguments
      process
      termination-target
      timeout
      input-producer
      stdout-capture
      stdout-sink
      stderr-capture
      stderr-sink)
    (let ((wait-status (%wait-for-process process timeout :stop-when-output-fails-p t)))
      (unless (eq wait-status :completed)
        (%terminate-process-group process termination-target))
      (sb-ext:process-wait process)
      (%make-program-result
        program
        arguments
        process
        timeout
        wait-status
        input-producer
        stdout-capture
        stdout-sink
        stderr-capture
        stderr-sink)))
  (defun %cleanup-program (process termination-target input-producer input-stream)
    (when input-producer
      (ignore-errors (%finish-input-producer input-producer)))
    (if (%process-terminal-p process) (ignore-errors (sb-ext:process-wait process))
      (ignore-errors (%terminate-process-group process termination-target)))
    (when input-stream
      (ignore-errors (close input-stream))))
  (defun %run-program (program
      arguments
      &key
      input
      (timeout +default-command-timeout-seconds+)
      environment
      directory
      (max-output-characters +default-command-output-limit+)
      input-writer
      output-consumer)
    (%validate-program-inputs
      program
      arguments
      input
      timeout
      environment
      directory
      max-output-characters)
    (when (and input input-writer)
      (error 'type-error :datum input :expected-type 'null))
    (multiple-value-bind (stdout-consumer stderr-consumer) (%make-program-output-consumers output-consumer)
      (let* ((input-stream (%make-program-input-stream input input-writer))
             (process
            (sb-ext:run-program
              program
              arguments
              :search
              t
              :wait
              nil
              :input
              input-stream
              :output
              :stream
              :error
              :stream
              :environment
              environment
              :directory
              (%normalize-program-directory directory)))
             (termination-target (%process-termination-target process))
             (stdout-capture nil)
             (stdout-sink nil)
             (stderr-capture nil)
             (stderr-sink nil)
             (input-producer nil))
        (unwind-protect (progn
            (multiple-value-setq
              (stdout-capture stdout-sink stderr-capture stderr-sink)
              (%start-program-output-captures
                process
                max-output-characters
                stdout-consumer
                stderr-consumer))
            (when input-writer
              (setf input-producer (%start-input-producer (sb-ext:process-input process) input-writer)))
            (%complete-program
              program
              arguments
              process
              termination-target
              timeout
              input-producer
              stdout-capture
              stdout-sink
              stderr-capture
              stderr-sink))
          (%cleanup-program process termination-target input-producer input-stream))))))

(progn
  #+sbcl
  (defun call-with-program-input (thunk program arguments
                                  &key
                                    (timeout +default-command-timeout-seconds+)
                                    environment
                                    directory
                                    (max-output-characters
                                      +default-command-output-limit+))
    "Run PROGRAM while THUNK writes its standard input.
THUNK is invoked on a dedicated worker thread with the writable child input
stream. The process output remains available in the returned PROCESS-RESULT."
    (check-type thunk function)
    (%run-program program arguments
                  :timeout timeout
                  :environment environment
                  :directory directory
                  :max-output-characters max-output-characters
                  :input-writer thunk))
  #-sbcl
  (defun call-with-program-input (thunk program arguments &rest keys)
    (declare (ignore thunk program arguments keys))
    (%unsupported 'call-with-program-input))
  (defmacro with-program-input ((stream program arguments &rest options) &body body)
    "Evaluate BODY with STREAM bound to PROGRAM's standard input stream."
    (unless (and (symbolp stream) (not (constantp stream)))
      (error "STREAM must be a non-constant symbol: ~S" stream))
    `(call-with-program-input
      (lambda (,stream)
        ,@body)
      ,program
      ,arguments
      ,@options)))

(progn
  #+sbcl
  (defun run-program (program arguments &key input
                                           (timeout +default-command-timeout-seconds+)
                                           environment
                                           directory
                                           (max-output-characters
                                             +default-command-output-limit+))
    "Run PROGRAM with ARGUMENTS without a shell and return a PROCESS-RESULT.
INPUT, when supplied, is a string written to the child standard input. Output
is captured concurrently and bounded by MAX-OUTPUT-CHARACTERS per channel."
    (%run-program program arguments
                  :input input
                  :timeout timeout
                  :environment environment
                  :directory directory
                  :max-output-characters max-output-characters))
  #-sbcl
  (defun run-program (program arguments &rest keys)
    (declare (ignore program arguments keys))
    (%unsupported 'run-program))

  (eval-when (:compile-toplevel :load-toplevel :execute)
    (defun %macro-variable-name-p (name)
      (and (symbolp name) (not (constantp name))))

    (defun %parse-program-input-clause (clause)
      (unless (and
               (consp clause)
               (eq (first clause) :input)
               (consp (second clause))
               (null (rest (second clause)))
               (%macro-variable-name-p (first (second clause))))
        (error "INPUT-CLAUSE must have the form (:INPUT (STREAM) . BODY): ~S"
               clause))
      (values (first (second clause)) (cddr clause)))

    (defun %parse-program-output-clause (clause)
      (unless (and
               (consp clause)
               (eq (first clause) :output)
               (consp (second clause))
               (consp (rest (second clause)))
               (null (cddr (second clause)))
               (%macro-variable-name-p (first (second clause)))
               (%macro-variable-name-p (second (second clause))))
        (error
         "OUTPUT-CLAUSE must have the form (:OUTPUT (CHANNEL CHARACTER) . BODY): ~S"
         clause))
      (values (first (second clause))
              (second (second clause))
              (cddr clause))))

  (defmacro with-program-output ((channel character program arguments &rest options) &body body)
    "Evaluate BODY for each character emitted by PROGRAM."
    (unless (%macro-variable-name-p channel)
      (error "CHANNEL must be a non-constant symbol: ~S" channel))
    (unless (%macro-variable-name-p character)
      (error "CHARACTER must be a non-constant symbol: ~S" character))
    `(call-with-program-output
      (lambda (,channel ,character)
        ,@body)
      ,program
      ,arguments
      ,@options))

  (defmacro with-program-io ((program arguments &rest options) input-clause output-clause)
    "Evaluate input and output clauses while streaming PROGRAM I/O.

INPUT-CLAUSE has the form (:INPUT (STREAM) . BODY). OUTPUT-CLAUSE has the
form (:OUTPUT (CHANNEL CHARACTER) . BODY)."
    (multiple-value-bind (stream input-body)
        (%parse-program-input-clause input-clause)
      (multiple-value-bind (channel character output-body)
          (%parse-program-output-clause output-clause)
        `(call-with-program-io
          (lambda (,stream)
            ,@input-body)
          (lambda (,channel ,character)
            ,@output-body)
          ,program
          ,arguments
          ,@options)))))

(defun call-with-program-result (thunk program arguments &rest options)
  "Run PROGRAM, then call THUNK with its PROCESS-RESULT, preserving values."
  (check-type thunk function)
  (funcall thunk (apply #'run-program program arguments options)))

(defmacro with-program-result ((result program arguments &rest options) &body body)
  "Evaluate BODY with RESULT lexically bound to RUN-PROGRAM's result."
  (unless (and (symbolp result) (not (constantp result)))
    (error "RESULT must be a non-constant symbol: ~S" result))
  `(call-with-program-result
    (lambda (,result)
      ,@body)
    ,program
    ,arguments
    ,@options))

#+sbcl
(progn
  (defun call-with-program-output (thunk program arguments &key input
                                                          (timeout +default-command-timeout-seconds+)
                                                          environment directory)
    "Run PROGRAM while calling THUNK for each output character.
THUNK receives a channel keyword, :STDOUT or :STDERR, and one character.
Each channel is drained on a dedicated thread, so calls from distinct channels
may interleave. The returned PROCESS-RESULT does not retain output."
    (check-type thunk function)
    (%run-program program arguments
                  :input input
                  :timeout timeout
                  :environment environment
                  :directory directory
                  :output-consumer thunk))

  (defun call-with-program-io (input-thunk output-thunk program arguments
                               &key
                                 (timeout +default-command-timeout-seconds+)
                                 environment
                                 directory)
    "Run PROGRAM while streaming standard input and output through callbacks.
INPUT-THUNK receives the writable standard-input stream on a dedicated worker.
OUTPUT-THUNK receives a channel keyword, :STDOUT or :STDERR, and one character
on a dedicated reader thread per channel. The returned PROCESS-RESULT does not
retain output."
    (check-type input-thunk function)
    (check-type output-thunk function)
    (%run-program program arguments
                  :timeout timeout
                  :environment environment
                  :directory directory
                  :input-writer input-thunk
                  :output-consumer output-thunk)))

#-sbcl
(progn
  (defun call-with-program-output (thunk program arguments &rest keys)
    (declare (ignore thunk program arguments keys))
    (%unsupported (quote call-with-program-output)))

  (defun call-with-program-io (input-thunk output-thunk program arguments &rest keys)
    (declare (ignore input-thunk output-thunk program arguments keys))
    (%unsupported (quote call-with-program-io))))
