;;;; cl-host-kit.asd
(asdf:defsystem "cl-host-kit"
  :description "Dependency-free host-environment toolkit for Common Lisp: pathnames, filesystem, environment variables, and direct program execution"
  :long-description "A dependency-free, direct host-environment API for
pathname, filesystem, environment-variable, direct-program-execution, and
string operations. It is intentionally not source-compatible with uiop and
uses SBCL's sb-posix as its only implementation dependency."
  :version "0.1.0"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-host-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-host-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-host-kit.git")
  ;; SB-POSIX is SBCL's own contrib (see CODING_STANDARD.md "sb-* dependencies
  ;; are implementation dependencies, not external ones"), gated on #+sbcl so
  ;; ASDF does not fail dependency resolution with a confusing "system
  ;; sb-posix not found" on a non-SBCL host; src/environment.lisp and
  ;; src/filesystem-metadata.lisp and src/directory-operations.lisp report a clear
  ;; unsupported-implementation condition
  ;; instead. This is cl-host-kit's complete dependency set.
  :depends-on (#+sbcl #:sb-posix)
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "strings")
               (:file "pathnames")
               (:file "environment")
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
