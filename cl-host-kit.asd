;;;; cl-host-kit.asd
(asdf:defsystem "cl-host-kit"
  :description "SBCL-native host-environment toolkit: pathnames, filesystem, and environment variables"
  :long-description "A deliberately narrow, SBCL-native toolkit for pathname, filesystem, environment-variable, and string-splitting operations. It exposes a documented subset of UIOP-shaped operations with the sb-posix contrib that SBCL provides as the only implementation dependency."
  :version "0.1.0"
  :author "Nerima Lisp"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-host-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-host-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-host-kit.git")
  :depends-on (#:sb-posix)
  :serial t
  :components
  ((:file "src/package")
   (:file "src/conditions")
   (:file "src/strings")
   (:file "src/pathnames")
   (:file "src/environment")
   (:file "src/working-directory")
   (:file "src/filesystem")))

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
  :components
  ((:file "package")
   (:file "conditions-test")
   (:file "strings-test")
   (:file "pathnames-test")
   (:file "environment-test")
   (:file "working-directory-test")
   (:file "filesystem-test"))
  :perform
  (asdf:test-op (operation component)
    (declare (ignore operation component))
    (unless (funcall (symbol-function (find-symbol "RUN-TESTS" "CL-HOST-KIT/TEST")))
      (error "cl-host-kit test suite failed"))))
