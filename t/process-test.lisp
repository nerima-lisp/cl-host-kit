;;;; t/process-test.lisp
(in-package #:cl-host-kit/test)

(progn
  (defparameter +shell+ "/bin/sh")
  (it
    "exposes positive default process limits"
    (expect +default-command-timeout-seconds+ :to-be-truthy)
    (expect (plusp +default-command-timeout-seconds+) :to-be-truthy)
    (expect (integerp +default-command-output-limit+) :to-be-truthy)
    (expect (plusp +default-command-output-limit+) :to-be-truthy)))

(describe
  "find-program"
  (it
    "finds an executable by explicit path and through PATH"
    (expect (find-program "/bin/sh") :to-equal (truename "/bin/sh"))
    (expect (find-program "sh" :path "/bin") :to-equal (truename "/bin/sh")))
  (it
    "treats empty PATH entries as the current directory and rejects missing programs"
    (with-temporary-directory
      (scratch :prefix "cl-host-kit-process-test-")
      (let ((program (merge-pathnames "host-kit-program" scratch)))
        (with-open-file (stream program :direction :output :if-exists :supersede)
          (write-string "not invoked" stream))
        (sb-posix:chmod (namestring program) #o700)
        (call-with-working-directory
          (lambda ()
            (expect (find-program "host-kit-program" :path "") :to-equal (truename program)))
          scratch))
      (expect
        (find-program "definitely-not-a-host-kit-program" :path "/bin")
        :to-be
        nil))))

(it
  "returns NIL when PATH is absent or an explicit pathname is not executable"
  (with-temporary-directory
    (scratch :prefix "cl-host-kit-process-test-")
    (let ((ordinary-file (merge-pathnames "ordinary-file" scratch)))
      (write-file-string "not executable" ordinary-file)
      (expect (find-program "sh" :path nil) :to-be nil)
      (expect (find-program (namestring ordinary-file)) :to-be nil)
      (expect (find-program (namestring scratch)) :to-be nil))))

(progn
(describe
  "run-program"
  (it
    "captures stdout, stderr, and a non-zero exit code without a shell wrapper"
    (let ((result (run-program +shell+ '("-c" "printf output; printf error >&2; exit 7"))))
      (expect (process-result-stdout result) :to-equal "output")
      (expect (process-result-stderr result) :to-equal "error")
      (expect (process-result-exit-code result) :to-equal 7)
      (expect (process-result-signal result) :to-be nil)))
  (it
    "turns unexpected terminal statuses into inspectable conditions"
    (let ((result (run-program +shell+ '("-c" "exit 7")))
          (condition nil))
      (handler-case (ensure-program-success result)
        (process-exit-error (caught)
          (setf condition caught)))
      (expect condition :to-be-truthy)
      (expect (process-exit-error-program condition) :to-equal +shell+)
      (expect (process-exit-error-arguments condition) :to-equal '("-c" "exit 7"))
      (expect (process-exit-error-exit-code condition) :to-equal 7)
      (expect (process-exit-error-signal condition) :to-be nil)
      (expect (process-exit-error-expected-exit-codes condition) :to-equal '(0))
      (expect (eq (process-exit-error-result condition) result) :to-be-truthy)
      (expect (format nil "~A" condition) :to-match "code 7")))
  (it
    "returns the original result for an expected terminal status"
    (let ((success (run-program +shell+ '("-c" "exit 0")))
          (custom-success (run-program +shell+ '("-c" "exit 3"))))
      (expect (eq (ensure-program-success success) success) :to-be-truthy)
      (expect
        (eq
          (ensure-program-success custom-success :expected-exit-codes '(0 3))
          custom-success)
        :to-be-truthy)))
  (it
    "validates success status inputs"
    (signals type-error (ensure-program-success :not-a-process-result))
    (signals
      type-error
      (ensure-program-success
        (run-program +shell+ '("-c" "exit 0"))
        :expected-exit-codes
        '(0 :not-an-exit-code))))
  (progn
  (it
      "validates program API inputs before starting a child"
    (signals type-error (find-program 1))
    (signals type-error (find-program "sh" :path 1))
    (signals type-error (run-program 1 '()))
    (signals type-error (run-program +shell+ :not-a-list))
    (signals type-error (run-program +shell+ '(:not-a-string)))
    (signals type-error (run-program +shell+ '() :input 1))
    (signals type-error (run-program +shell+ '() :timeout -1))
    (signals type-error (run-program +shell+ '() :environment '(:not-a-string)))
    (dolist (environment
        (list
          '("MISSING-SEPARATOR")
          '("=missing-name")
          (list (format nil "BAD~CNAME=value" #\Null))
          (list (format nil "NAME=bad~Cvalue" #\Null))))
      (signals type-error (run-program +shell+ '() :environment environment)))
    (signals type-error (run-program +shell+ '() :directory :not-a-pathname))
    (signals type-error (run-program +shell+ '() :max-output-characters -1))
    (signals type-error (call-with-program-result :not-a-function +shell+ '())))
  (it
      "rejects circular list inputs before starting a child"
    (let ((arguments (list "-c" "exit 0"))
          (environment (list "HOST_KIT_TEST=value"))
          (expected-exit-codes (list 0))
          (result (run-program +shell+ '("-c" "exit 0")))
          (signalled-p nil))
      (setf (cdr arguments) arguments
            (cdr environment) environment
            (cdr expected-exit-codes) expected-exit-codes)
      (handler-case
          (run-program +shell+ arguments)
        (type-error () (setf signalled-p t)))
      (expect signalled-p :to-be-truthy)
      (setf signalled-p nil)
      (handler-case
          (run-program +shell+ '() :environment environment)
        (type-error () (setf signalled-p t)))
      (expect signalled-p :to-be-truthy)
      (setf signalled-p nil)
      (handler-case
          (ensure-program-success result :expected-exit-codes expected-exit-codes)
        (type-error () (setf signalled-p t)))
      (expect signalled-p :to-be-truthy))))
  (it
    "feeds string input to the child"
    (let ((result (run-program +shell+ '("-c" "cat") :input "input-data")))
      (expect (process-result-stdout result) :to-equal "input-data")
      (expect (process-result-exit-code result) :to-equal 0)))
  (it
    "uses supplied child environment data and an absolute working directory"
    (with-temporary-directory
      (scratch :prefix "cl-host-kit-process-test-")
      (let ((result
            (run-program
              +shell+
              '("-c"
                "test \"$(pwd -P)/\" = \"$HOST_KIT_EXPECTED_DIRECTORY\" && printf %s \"$HOST_KIT_CHILD_ENV\"")
              :environment
              (list
                "HOST_KIT_CHILD_ENV=present=again"
                (format nil "HOST_KIT_EXPECTED_DIRECTORY=~A" (namestring (truename scratch))))
              :directory
              scratch)))
        (expect (process-result-exit-code result) :to-equal 0)
        (expect (process-result-stdout result) :to-equal "present=again"))))
  (it
    "resolves a relative child directory against the process working directory"
    (with-temporary-directory
      (scratch :prefix "cl-host-kit-process-test-")
      (with-working-directory
        (scratch)
        (let ((result
              (run-program
                +shell+
                '("-c" "test \"$(pwd -P)/\" = \"$HOST_KIT_EXPECTED_DIRECTORY\"")
                :environment
                (list
                  (format nil "HOST_KIT_EXPECTED_DIRECTORY=~A" (namestring (truename scratch))))
                :directory
                ".")))
          (expect (process-result-exit-code result) :to-equal 0)))))
  (it
    "returns promptly when a descendant keeps an output descriptor open"
    (let* ((started-at (get-internal-real-time))
           (result (run-program +shell+ '("-c" "sleep 5 & printf done") :timeout 0.5d0))
           (elapsed-seconds
          (/ (- (get-internal-real-time) started-at) internal-time-units-per-second)))
      (expect (process-result-stdout result) :to-equal "done")
      (expect (< elapsed-seconds 1d0) :to-be-truthy)))
  (it
    "bounds each captured output stream while continuing to drain both"
    (let ((result
          (run-program
            +shell+
            '("-c" "printf 1234; printf abcdef >&2")
            :max-output-characters
            3)))
      (expect (process-result-stdout result) :to-equal "123")
      (expect (process-result-stderr result) :to-equal "abc")
      (expect (process-result-stdout-truncated-p result) :to-be-truthy)
      (expect (process-result-stderr-truncated-p result) :to-be-truthy)))
  (it
    "records signal termination independently from an exit code"
    (let* ((result (run-program +shell+ '("-c" "kill -TERM $$")))
           (condition nil))
      (expect (process-result-exit-code result) :to-be nil)
      (expect (process-result-signal result) :to-be-truthy)
      (handler-case (ensure-program-success result)
        (process-exit-error (caught)
          (setf condition caught)))
      (expect
        (process-exit-error-signal condition)
        :to-equal
        (process-result-signal result))
      (expect (format nil "~A" condition) :to-match "signal")))
  (it
    "signals a timeout with the partial result after terminating the child"
    (let ((condition nil))
      (handler-case (run-program +shell+ '("-c" "sleep 1") :timeout 0.05d0)
        (process-timeout (caught)
          (setf condition caught)))
      (expect condition :to-be-truthy)
      (expect (process-timeout-program condition) :to-equal +shell+)
      (expect (process-timeout-arguments condition) :to-equal '("-c" "sleep 1"))
      (expect (process-timeout-seconds condition) :to-equal 0.05d0)
      (expect
        (process-result-timed-out-p (process-timeout-result condition))
        :to-be-truthy)))
  (it
    "terminates timeout descendants before they can perform later side effects"
    (with-temporary-directory
      (scratch :prefix "cl-host-kit-process-test-")
      (let ((marker (merge-pathnames "descendant-ran" scratch)))
        (signals
          process-timeout
          (run-program
            +shell+
            (list "-c" (format nil "(sleep 1; : > ~S) & sleep 30" (namestring marker)))
            :timeout
            0.05d0))
        (sleep 1.1d0)
        (expect (probe-file marker) :to-be nil))))
  (it
    "binds a program result while preserving the body values"
    (expect
      (multiple-value-list
        (with-program-result
          (result +shell+ '("-c" "printf macro"))
          (values (process-result-stdout result) :preserved)))
      :to-equal
      '("macro" :preserved))))
(it
  "terminates a started child when output capture initialization fails"
  (with-temporary-directory
    (scratch :prefix "cl-host-kit-process-test-")
    (let* ((marker (merge-pathnames "initialization-descendant-ran" scratch))
           (function-symbol (quote host-kit::%start-output-capture))
           (original-function (symbol-function function-symbol)))
      (unwind-protect
          (progn
            (setf (symbol-function function-symbol)
                  (lambda (&rest arguments)
                    (declare (ignore arguments))
                    (error "output capture initialization failed")))
            (signals
              error
              (run-program
                +shell+
                (list
                  "-c"
                  (format nil "(sleep 1; : > ~S) & sleep 30" (namestring marker)))))
            (sleep 1.1d0)
            (expect (probe-file marker) :to-be nil))
        (setf (symbol-function function-symbol) original-function)))))
)

(progn
  (it
    "drains large bidirectional streams without blocking"
    (let* ((input (make-string (1+ (* 1024 1024)) :initial-element #\x))
           (result
          (run-program
            +shell+
            '("-c" "cat")
            :input
            input
            :max-output-characters
            (length input))))
      (expect (process-result-exit-code result) :to-equal 0)
      (expect (process-result-stdout result) :to-equal input)
      (expect (process-result-stdout-truncated-p result) :to-be nil)))
  (describe
    "call-with-program-output"
    (it
      "streams both channels without retaining output in the result"
      (let ((stdout (make-string-output-stream))
            (stderr (make-string-output-stream))
            (mutex (sb-thread:make-mutex :name "program-output test")))
        (let ((result
              (call-with-program-output
                (lambda (channel character)
                  (sb-thread:with-mutex
                    (mutex)
                    (ecase channel
                      (:stdout (write-char character stdout))
                      (:stderr (write-char character stderr)))))
                +shell+
                (quote ("-c" "printf output; printf error >&2")))))
          (expect (get-output-stream-string stdout) :to-equal "output")
          (expect (get-output-stream-string stderr) :to-equal "error")
          (expect (process-result-stdout result) :to-equal "")
          (expect (process-result-stderr result) :to-equal "")
          (expect (process-result-stdout-truncated-p result) :to-be nil)
          (expect (process-result-stderr-truncated-p result) :to-be nil)
          (expect (process-result-exit-code result) :to-equal 0))))
    (it
      "propagates callback failures without reporting a timeout"
      (let ((condition nil))
        (handler-case
            (call-with-program-output
              (lambda (channel character)
                (declare (ignore channel character))
                (error "callback failed"))
              +shell+
              (quote ("-c" "printf output")))
          (error (caught)
            (setf condition caught)))
        (expect condition :to-be-truthy)
        (expect (typep condition 'process-timeout) :to-be nil)))
    (it
      "terminates callback-failure descendants before later side effects"
      (with-temporary-directory
        (scratch :prefix "cl-host-kit-process-test-")
        (let ((marker (merge-pathnames "callback-descendant-ran" scratch))
              (started-at (get-internal-real-time))
              (condition nil))
          (handler-case
              (call-with-program-output
                (lambda (channel character)
                  (declare (ignore channel character))
                  (error "callback failed"))
                +shell+
                (list
                  "-c"
                  (format nil "(sleep 1; : > ~S) & printf output; sleep 30"
                          (namestring marker)))
                :timeout
                2d0)
            (error (caught)
              (setf condition caught)))
          (expect condition :to-be-truthy)
          (expect (typep condition 'process-timeout) :to-be nil)
          (expect
            (< (/ (- (get-internal-real-time) started-at)
                  internal-time-units-per-second)
               1d0)
            :to-be-truthy)
          (sleep 1.1d0)
          (expect (probe-file marker) :to-be nil))))
    (it
      "provides a lexical macro interface"
      (let ((characters nil))
        (let ((result
              (with-program-output
                (channel character +shell+ (quote ("-c" "printf macro")))
                (when (eq channel :stdout)
                  (push character characters)))))
          (expect (coerce (nreverse characters) (quote string)) :to-equal "macro")
          (expect (process-result-exit-code result) :to-equal 0))))
    (it
      "validates the callback before starting a child"
      (signals
        type-error
        (call-with-program-output :not-a-function +shell+ (quote ())))))
  (describe
    "call-with-program-input"
    (it
      "streams incrementally and captures the child output"
      (let ((result
            (call-with-program-input
              (lambda (stream)
                (write-string "first " stream)
                (write-string "second" stream))
              +shell+
              (quote ("-c" "cat")))))
        (expect (process-result-stdout result) :to-equal "first second")
        (expect (process-result-exit-code result) :to-equal 0)))
    (it
      "provides a lexical macro interface"
      (let ((result
            (with-program-input
              (stream +shell+ (quote ("-c" "cat")))
              (write-string "macro" stream))))
        (expect (process-result-stdout result) :to-equal "macro")
        (expect (process-result-exit-code result) :to-equal 0)))
    (it
      "propagates callback failures after reaping the child"
      (signals
        error
        (call-with-program-input
          (lambda (stream)
            (write-string "partial" stream)
            (error "input callback failed"))
          +shell+
          (quote ("-c" "cat")))))
    (it
      "returns promptly when a timed-out input callback does not finish"
      (let ((started-at (get-internal-real-time)))
        (signals
          process-timeout
          (call-with-program-input
            (lambda (stream)
              (declare (ignore stream))
              (sleep 5d0))
            +shell+
            (quote ("-c" "sleep 30"))
            :timeout
            0.01d0))
        (expect (< (/ (- (get-internal-real-time) started-at)
                      internal-time-units-per-second)
                   1d0)
                :to-be-truthy)))
    (it
      "validates the callback before starting a child"
      (signals
        type-error
        (call-with-program-input :not-a-function +shell+ (quote ())))))
  (describe
    "call-with-program-io"
    (it
      "streams input and both output channels without retaining output"
      (let ((stdout (make-string-output-stream))
            (stderr (make-string-output-stream))
            (mutex (sb-thread:make-mutex :name "program-io test")))
        (let ((result
              (call-with-program-io
                (lambda (stream)
                  (write-string "request" stream))
                (lambda (channel character)
                  (sb-thread:with-mutex
                    (mutex)
                    (ecase channel
                      (:stdout (write-char character stdout))
                      (:stderr (write-char character stderr)))))
                +shell+
                (quote ("-c" "cat; printf response >&2")))))
          (expect (get-output-stream-string stdout) :to-equal "request")
          (expect (get-output-stream-string stderr) :to-equal "response")
          (expect (process-result-stdout result) :to-equal "")
          (expect (process-result-stderr result) :to-equal "")
          (expect (process-result-exit-code result) :to-equal 0))))
    (it
      "provides lexical input and output clauses"
      (let ((stdout (make-string-output-stream))
            (mutex (sb-thread:make-mutex :name "with-program-io test")))
        (let ((result
              (with-program-io
                (+shell+ (quote ("-c" "cat")))
                (:input (stream) (write-string "macro request" stream))
                (:output
                  (channel character)
                  (when (eq channel :stdout)
                    (sb-thread:with-mutex (mutex) (write-char character stdout)))))))
          (expect (get-output-stream-string stdout) :to-equal "macro request")
          (expect (process-result-stdout result) :to-equal "")
          (expect (process-result-stderr result) :to-equal "")
          (expect (process-result-exit-code result) :to-equal 0))))
    (progn
  (it
    "propagates callback failures after reaping the child"
    (signals
      error
      (call-with-program-io
        (lambda (stream)
          (declare (ignore stream))
          (error "input callback failed"))
        (lambda (channel character)
          (declare (ignore channel character)))
        +shell+
        (quote ("-c" "cat"))))
    (signals
      error
      (call-with-program-io
        (lambda (stream)
          (write-string "request" stream))
        (lambda (channel character)
          (declare (ignore channel character))
          (error "output callback failed"))
        +shell+
        (quote ("-c" "cat")))))
  (it
    "closes output when a callback fails so a producer cannot block"
    (let ((started-at (get-internal-real-time)))
      (signals
        error
        (call-with-program-io
          (lambda (stream)
            (declare (ignore stream)))
          (lambda (channel character)
            (declare (ignore channel character))
            (error "output callback failed"))
          +shell+
          (quote ("-c" "while :; do printf 0123456789; done"))
          :timeout 2d0))
      (expect (< (/ (- (get-internal-real-time) started-at)
                    internal-time-units-per-second)
                 1d0)
              :to-be-truthy)))))
  (it
    "rejects constant lexical bindings during macroexpansion"
    (dolist
      (form
        (quote
          ((with-program-input (t "program" (quote ())) nil)
           (with-program-input (42 "program" (quote ())) nil)
           (with-program-result (nil "program" (quote ())) nil)
           (with-program-result (42 "program" (quote ())) nil)
           (with-program-output (t character "program" (quote ())) nil)
           (with-program-output (42 character "program" (quote ())) nil)
           (with-program-output (channel t "program" (quote ())) nil)
           (with-program-output (channel 42 "program" (quote ())) nil))))
      (signals error (macroexpand-1 form))))
  (it
    "rejects malformed streaming I/O clauses during macroexpansion"
    (dolist
      (form
        (quote
          ((with-program-io
             ("program" (quote ()))
             (:unexpected (stream) nil)
             (:output (channel character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (t) nil)
             (:output (channel character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input invalid-parameters nil)
             (:output (channel character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (42) nil)
             (:output (channel character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream extra) nil)
             (:output (channel character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:unexpected (channel character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:output invalid-parameters nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:output (channel) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:output (channel t) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:output (42 character) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:output (channel 42) nil))
           (with-program-io
             ("program" (quote ()))
             (:input (stream) nil)
             (:output (channel character extra) nil)))))
      (signals error (macroexpand-1 form))))
)
