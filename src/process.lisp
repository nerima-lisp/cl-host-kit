;;;; src/process.lisp
;;;;
;;;; RUN-PROGRAM and its CPS scope macros: a small direct SBCL process API
;;;; that accepts an argv list rather than shell text. Orchestrates
;;;; PROCESS-RESULT (process-result.lisp) and the concurrent capture engine
;;;; (process-io.lisp) into the public entry points.
(in-package #:host-kit)

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
            ;; SBCL's RUN-PROGRAM inherits the caller's process environment
            ;; only when :ENVIRONMENT is absent from the call, not merely NIL
            ;; -- passing it unconditionally would launch every child with an
            ;; empty environment (no PATH, no HOME) whenever ENVIRONMENT is
            ;; NIL here. Omit the keyword entirely in that case.
            (apply
              #'sb-ext:run-program
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
              :directory
              (%normalize-program-directory directory)
              (when environment (list :environment environment))))
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
  (define-with-macro with-program-input (stream) call-with-program-input))

(progn
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

  (eval-when (:compile-toplevel :load-toplevel :execute)
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

  (define-with-macro with-program-output (channel character) call-with-program-output)

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

(define-with-macro with-program-result (result) call-with-program-result)

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
