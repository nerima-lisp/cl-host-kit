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
      (expect (format nil "~A" condition) :to-match "CHDIR")
      (expect (format nil "~A" condition) :to-match "/nope")
      (expect (format nil "~A" condition) :to-match "no such directory")))
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
        (format nil "~A" condition)
        :to-equal
        "HOST-KIT operation :GETCWD failed: failure"))))
