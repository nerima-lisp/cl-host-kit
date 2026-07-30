;;;; cl-host-kit.asd
(asdf:defsystem "cl-host-kit"
  :description "SBCL-native host-environment toolkit: pathnames, filesystem, environment variables, and direct program execution"
  :long-description "A deliberately narrow, SBCL-native toolkit for pathname,
filesystem, environment-variable, direct-program-execution, and
string-splitting operations. It exposes a documented subset of UIOP-shaped
operations with the sb-posix contrib that SBCL provides as the only
implementation dependency."
  :version "0.1.0"
  :author "Nerima Lisp"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-host-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-host-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-host-kit.git")
  :depends-on (#:sb-posix)
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "with-macros")
               (:file "strings")
               (:file "pathnames")
               (:file "environment")
               (:file "process-result")
               (:file "process-io")
               (:file "process")
               (:file "working-directory")
               (:file "filesystem-metadata")
               (:file "directory-operations")
               (:file "temporary-resources")
               (:file "file-io")
               (:file "file-locking"))
  :in-order-to ((asdf:test-op (asdf:test-op "cl-host-kit/test"))))

(asdf:defsystem "cl-host-kit/test"
  :description "Test system for cl-host-kit"
  :version "0.1.0"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-host-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-host-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-host-kit.git")
  :depends-on ("cl-host-kit" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "conditions-test")
               (:file "strings-test")
               (:file "pathnames-test")
               (:file "environment-test")
               (:file "process-test")
               (:file "process-streaming-test")
               (:file "working-directory-test")
               (:file "filesystem-test-support")
               (:file "filesystem-metadata-test")
               (:file "directory-operations-test")
               (:file "temporary-resources-test")
               (:file "file-io-test")
               (:file "file-locking-test"))
  :perform (asdf:test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-HOST-KIT/TEST")))
               (error "cl-host-kit test suite failed"))))
