;;;; t/conditions-test.lisp
(in-package #:cl-host-kit/test)

(describe
  "host-kit-error"
  (it
    "is a subtype of ERROR"
    (expect (subtypep 'host-kit-error 'error) :to-be-truthy)))

(describe
  "host-operation-failed"
  (it
    "carries the operation, target, and reason it was signalled with"
    (let ((condition
          (make-condition
            'host-operation-failed
            :operation
            :some-op
            :target
            "/some/path"
            :reason
            "boom")))
      (expect (host-operation-failed-operation condition) :to-equal :some-op)
      (expect (host-operation-failed-target condition) :to-equal "/some/path")
      (expect (host-operation-failed-reason condition) :to-equal "boom")))
  (it
    "reports the operation, target, and reason in its :report"
    (let ((condition
          (make-condition
            'host-operation-failed
            :operation
            :chdir
            :target
            "/nope"
            :reason
            "no such directory")))
      (expect (princ-to-string condition) :to-match "CHDIR")
      (expect (princ-to-string condition) :to-match "/nope")
      (expect (princ-to-string condition) :to-match "no such directory")))
  (it
    "is a subtype of HOST-KIT-ERROR"
    (expect (subtypep 'host-operation-failed 'host-kit-error) :to-be-truthy)))

(describe
  "internal condition helpers"
  (it
    "returns a successful body value unchanged"
    (expect
      (host-kit::%with-host-operation (:test-operation nil) :result)
      :to-equal
      :result))
  (it
    "wraps an ordinary error with operation metadata"
    (let ((condition
          (handler-case (host-kit::%with-host-operation (:test-operation "target") (error "boom"))
            (host-operation-failed (condition)
              condition))))
      (expect (host-operation-failed-operation condition) :to-equal :test-operation)
      (expect (host-operation-failed-target condition) :to-equal "target")
      (expect (host-operation-failed-reason condition) :to-be-truthy)))
  (it
    "expands the host operation wrapper"
    (expect
      (macroexpand-1
        (quote (host-kit::%with-host-operation (:test-operation "target") :result)))
      :to-be-truthy))
  (it
    "preserves an existing host-kit condition"
    (let ((condition
          (handler-case (host-kit::%with-host-operation
              (:test-operation "target")
              (error (make-condition (quote host-kit-error))))
            (host-kit-error (condition)
              condition))))
      (expect (typep condition (quote host-kit-error)) :to-be-truthy)
      (expect (typep condition (quote host-operation-failed)) :to-be-falsy)))
  (it
    "omits the target clause when a failure has no target"
    (let ((condition
          (make-condition
            (quote host-operation-failed)
            :operation :getcwd
            :target nil
            :reason "failure")))
      (expect
        (princ-to-string condition)
        :to-equal
        "HOST-KIT operation :GETCWD failed: failure"))))

(describe "process and timeout conditions"
  (it "carries terminal status details without including output in its report"
    (let ((condition (make-condition 'process-exit-error
                                     :program "/bin/example"
                                     :arguments '("--option")
                                     :exit-code nil
                                     :signal 15
                                     :expected-exit-codes '(0)
                                     :result :opaque-result)))
      (expect (process-exit-error-program condition) :to-equal "/bin/example")
      (expect (process-exit-error-arguments condition) :to-equal '("--option"))
      (expect (process-exit-error-exit-code condition) :to-be nil)
      (expect (process-exit-error-signal condition) :to-equal 15)
      (expect (process-exit-error-expected-exit-codes condition) :to-equal '(0))
      (expect (process-exit-error-result condition) :to-equal :opaque-result)
      (expect (princ-to-string condition) :to-match "signal 15")
      (expect (princ-to-string condition) :not :to-match "opaque-result")))

  (it "reports a nonzero exit code when no signal terminated the process"
    (let ((condition (make-condition 'process-exit-error
                                     :program "false"
                                     :arguments nil
                                     :exit-code 1
                                     :signal nil
                                     :expected-exit-codes '(0)
                                     :result nil)))
      (expect (princ-to-string condition) :to-match "code 1")))

  (it "reports a program timeout and retains command details"
    (let ((condition (make-condition 'process-timeout
                                     :program "sleep"
                                     :arguments '("1")
                                     :seconds 0.125
                                     :result :result)))
      (expect (process-timeout-program condition) :to-equal "sleep")
      (expect (process-timeout-arguments condition) :to-equal '("1"))
      (expect (process-timeout-seconds condition) :to-equal 0.125)
      (expect (process-timeout-result condition) :to-equal :result)
      (expect (princ-to-string condition) :to-match "0.125")))

  (it "reports advisory lock acquisition timeouts"
    (let ((condition (make-condition 'file-lock-timeout :seconds 2.5)))
      (expect (file-lock-timeout-seconds condition) :to-equal 2.5)
      (expect (princ-to-string condition) :to-match "2.500")))

  (it "keeps every concrete condition under HOST-KIT-ERROR"
    (dolist (type '(process-exit-error process-timeout file-lock-timeout))
      (expect (subtypep type 'host-kit-error) :to-be-truthy))))


(defun %api-reference-contents ()
  "Read the checked-in API reference from the ASDF system root."
  (let ((pathname (merge-pathnames "docs/src/api-reference.md"
                                   (asdf:system-source-directory "cl-host-kit"))))
    (with-open-file (stream pathname :direction :input)
      (let ((contents (make-string (file-length stream))))
        (read-sequence contents stream)
        contents))))

(defun %api-reference-symbol-mentioned-p (reference symbol)
  "Return true when SYMBOL occurs as a complete API name in REFERENCE."
  (let ((name (string-downcase (symbol-name symbol))))
    (or (search (concatenate 'string "`" name "`") reference)
        (loop
          with marker = (concatenate 'string "(" name)
          with limit = (length reference)
          with start = 0
          do
             (let ((position (search marker reference :start2 start)))
               (unless position
                 (return))
               (let ((boundary (+ position (length marker))))
                 (when (or (= boundary limit)
                           (char= (char reference boundary) #\))
                           (find (char reference boundary)
                                 (list #\Space #\Tab #\Newline #\Return)))
                   (return t))
                 (setf start (1+ position))))))))

(defun %public-symbols-missing-api-reference (reference)
  "Return exported HOST-KIT symbols without an API entry."
  (let ((package (find-package '#:host-kit))
        (missing nil))
    (do-external-symbols (symbol package (nreverse missing))
      (unless (%api-reference-symbol-mentioned-p reference symbol)
        (push symbol missing)))))

(describe "API reference contract"
  (it "mentions every public HOST-KIT symbol"
    (expect (%public-symbols-missing-api-reference (%api-reference-contents))
            :to-equal nil)))
