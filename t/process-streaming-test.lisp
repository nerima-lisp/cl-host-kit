;;;; t/process-streaming-test.lisp
;;;;
;;;; The character-streaming CALL-WITH-PROGRAM-OUTPUT/INPUT/IO family, split
;;;; out of process-test.lisp: run-program's buffered core is a distinct
;;;; concern from these callback-driven, concurrently-drained channels.
(in-package #:cl-host-kit/test)

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
  (progn
    (it-each ((t) (42))
        "rejects ~S as a WITH-PROGRAM-INPUT stream binding during macroexpansion"
        (invalid-stream)
      (signals error (macroexpand-1 `(with-program-input (,invalid-stream "program" (quote ())) nil))))
    (it-each ((nil) (42))
        "rejects ~S as a WITH-PROGRAM-RESULT result binding during macroexpansion"
        (invalid-result)
      (signals error (macroexpand-1 `(with-program-result (,invalid-result "program" (quote ())) nil))))
    (it-each ((t (quote character)) (42 (quote character)) ((quote channel) t) ((quote channel) 42))
        "rejects ~S ~S as a WITH-PROGRAM-OUTPUT channel/character binding pair during macroexpansion"
        (invalid-channel invalid-character)
      (signals error (macroexpand-1 `(with-program-output (,invalid-channel ,invalid-character "program" (quote ())) nil)))))
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
