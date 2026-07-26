;;;; cl-host-kit.asd
(asdf:defsystem "cl-host-kit"
  :description "Dependency-free host-environment toolkit for Common Lisp: pathnames, filesystem, and environment variables"
  :long-description "A from-scratch, modern-language-flavored replacement for
the pathname, filesystem, environment-variable, and string-splitting corner
of uiop -- covering exactly the subset of that surface nerima-lisp's own
source code actually calls, with SBCL's sb-posix as the only implementation
dependency."
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
  ;; src/filesystem.lisp report a clear unsupported-implementation condition
  ;; instead. This is cl-host-kit's complete dependency set.
  :depends-on (#+sbcl #:sb-posix)
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "strings")
               (:file "pathnames")
               (:file "environment")
               (:file "working-directory")
               (:file "filesystem"))
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
               (:file "working-directory-test")
               (:file "filesystem-test"))
  :perform (asdf:test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-HOST-KIT/TEST")))
               (error "cl-host-kit test suite failed"))))
