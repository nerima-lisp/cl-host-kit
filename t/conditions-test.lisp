;;;; t/conditions-test.lisp
;;;; t/conditions-test.lisp
(in-package #:cl-host-kit/test)

(describe "host-kit-error"
  (it "is a subtype of ERROR"
    (expect (subtypep 'host-kit-error 'error) :to-be-truthy)))

(describe "host-operation-failed"
  (it "carries the operation, target, and reason it was signalled with"
    (let ((condition (make-condition 'host-operation-failed
                                      :operation :some-op
                                      :target "/some/path"
                                      :reason "boom")))
      (expect (host-operation-failed-operation condition) :to-equal :some-op)
      (expect (host-operation-failed-target condition) :to-equal "/some/path")
      (expect (host-operation-failed-reason condition) :to-equal "boom")))

  (it "reports the operation, target, and reason in its :report"
    (let ((condition (make-condition 'host-operation-failed
                                      :operation :chdir
                                      :target "/nope"
                                      :reason "no such directory")))
      (expect (format nil "~A" condition) :to-match "CHDIR")
      (expect (format nil "~A" condition) :to-match "/nope")
      (expect (format nil "~A" condition) :to-match "no such directory")))

  (it "is a subtype of HOST-KIT-ERROR"
    (expect (subtypep 'host-operation-failed 'host-kit-error) :to-be-truthy)))

(describe "%with-host-operation"
  (it "wraps a non-host error with the requested operation and target"
    (handler-case
        (host-kit::%with-host-operation (:read-file "/missing")
          (error "expected test failure"))
      (host-operation-failed (condition)
        (expect (host-operation-failed-operation condition) :to-equal :read-file)
        (expect (host-operation-failed-target condition) :to-equal "/missing")
        (expect (format nil "~A" (host-operation-failed-reason condition))
                :to-match "expected test failure"))))

  (it "re-signals an existing host-kit error without adding a wrapper"
    (let ((original (make-condition 'host-operation-failed
                                    :operation :inner
                                    :target "/inner"
                                    :reason "inner failure")))
      (handler-case
          (host-kit::%with-host-operation (:outer "/outer")
            (error original))
        (host-operation-failed (condition)
          (expect condition :to-be original)
          (expect (host-operation-failed-operation condition) :to-equal :inner)
          (expect (host-operation-failed-target condition) :to-equal "/inner"))))))

(describe "unsupported-implementation"
  (it "is signalled with the requested feature by the unsupported helper"
    (handler-case
        (host-kit::%unsupported :getcwd)
      (unsupported-implementation (condition)
        (expect (unsupported-implementation-feature condition) :to-equal :getcwd))))

  (it "carries the feature it was signalled for"
    (let ((condition (make-condition 'unsupported-implementation :feature 'quit)))
      (expect (unsupported-implementation-feature condition) :to-equal 'quit)))

  (it "reports the feature name in its :report"
    (let ((condition (make-condition 'unsupported-implementation :feature 'quit)))
      (expect (format nil "~A" condition) :to-match "QUIT")))

  (it "is a subtype of HOST-KIT-ERROR"
    (expect (subtypep 'unsupported-implementation 'host-kit-error) :to-be-truthy)))

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
      (expect (format nil "~A" condition) :to-match "signal 15")
      (expect (format nil "~A" condition) :not :to-match "opaque-result")))

  (it "reports a nonzero exit code when no signal terminated the process"
    (let ((condition (make-condition 'process-exit-error
                                     :program "false"
                                     :arguments nil
                                     :exit-code 1
                                     :signal nil
                                     :expected-exit-codes '(0)
                                     :result nil)))
      (expect (format nil "~A" condition) :to-match "code 1")))

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
      (expect (format nil "~A" condition) :to-match "0.125")))

  (it "reports advisory lock acquisition timeouts"
    (let ((condition (make-condition 'file-lock-timeout :seconds 2.5)))
      (expect (file-lock-timeout-seconds condition) :to-equal 2.5)
      (expect (format nil "~A" condition) :to-match "2.500")))

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
                 (return nil))
               (let ((boundary (+ position (length marker))))
                 (when (or (= boundary limit)
                           (char= (char reference boundary) (code-char 41))
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
