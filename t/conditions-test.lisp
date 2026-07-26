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

(describe "unsupported-implementation"
  (it "carries the feature it was signalled for"
    (let ((condition (make-condition 'unsupported-implementation :feature 'quit)))
      (expect (unsupported-implementation-feature condition) :to-equal 'quit)))

  (it "reports the feature name in its :report"
    (let ((condition (make-condition 'unsupported-implementation :feature 'quit)))
      (expect (format nil "~A" condition) :to-match "QUIT")))

  (it "is a subtype of HOST-KIT-ERROR"
    (expect (subtypep 'unsupported-implementation 'host-kit-error) :to-be-truthy)))
