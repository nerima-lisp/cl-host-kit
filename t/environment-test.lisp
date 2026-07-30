;;;; t/environment-test.lisp
;;;
;;; QUIT wraps SB-EXT:EXIT, so its behavior is verified in a separate SBCL
;;; process rather than terminating the test runner.
(in-package #:cl-host-kit/test)

(describe
  "getenv"
  (it
    "returns NIL for an unset variable"
    (expect (getenv "CL_HOST_KIT_TEST_DEFINITELY_UNSET") :to-be nil))
  (it
    "returns the value SETF wrote"
    (unwind-protect (progn
        (setf (getenv "CL_HOST_KIT_TEST_VAR") "42")
        (expect (getenv "CL_HOST_KIT_TEST_VAR") :to-equal "42"))
      (setf (getenv "CL_HOST_KIT_TEST_VAR") nil)))
  (it
    "SETF to NIL unsets the variable"
    (setf (getenv "CL_HOST_KIT_TEST_VAR2") "x")
    (setf (getenv "CL_HOST_KIT_TEST_VAR2") nil)
    (expect (getenv "CL_HOST_KIT_TEST_VAR2") :to-be nil))
  (it
    "rejects invalid POSIX names and values"
    (signals type-error (getenv ""))
    (signals type-error (getenv "NAME=VALUE"))
    (signals type-error (getenv (format nil "NAME~CWITH_NUL" #\Null)))
    (signals
      type-error
      (setf (getenv "VALID_NAME") (format nil "value~Cwith-nul" #\Null)))))

(describe
  "environment-variables"
  (it
    "returns a NAME=VALUE snapshot suitable for child-process environments"
    (let ((name "CL_HOST_KIT_ENVIRONMENT_VARIABLES_TEST"))
      (unwind-protect (progn
          (setf (getenv name) "left=right")
          (let ((entry (format nil "~A=left=right" name)))
            (expect (find entry (environment-variables) :test #'string=) :to-equal entry)))
        (setf (getenv name) nil))))
  (it
    "returns strings independent from the process environment"
    (let ((name "CL_HOST_KIT_ENVIRONMENT_SNAPSHOT_TEST"))
      (unwind-protect (progn
          (setf (getenv name) "original")
          (let* ((entry (format nil "~A=original" name))
                 (snapshot-entry (find entry (environment-variables) :test #'string=)))
            (setf (char snapshot-entry 0) #\X)
            (expect (getenv name) :to-equal "original")
            (expect (find entry (environment-variables) :test #'string=) :to-equal entry)))
        (setf (getenv name) nil)))))

(describe
  "call-with-environment-variable"
  (it
    "returns every value from the callback and restores an unset variable"
    (let ((name "CL_HOST_KIT_SCOPED_ENV_UNSET_TEST"))
      (unwind-protect (progn
          (setf (getenv name) nil)
          (expect
            (multiple-value-list
              (call-with-environment-variable
                (lambda ()
                  (expect (getenv name) :to-equal "temporary")
                  (values :first :second))
                name
                "temporary"))
            :to-equal
            '(:first :second))
          (expect (getenv name) :to-be nil))
        (setf (getenv name) nil))))
  (it
    "restores an existing value when the callback signals"
    (let ((name "CL_HOST_KIT_SCOPED_ENV_ERROR_TEST"))
      (unwind-protect (progn
          (setf (getenv name) "before")
          (handler-case (call-with-environment-variable
              (lambda ()
                (expect (getenv name) :to-equal "temporary")
                (error "expected test failure"))
              name
              "temporary")
            (error ()
              nil))
          (expect (getenv name) :to-equal "before"))
        (setf (getenv name) nil))))
  (it
    "validates the callback, name, and value"
    (signals
      type-error
      (call-with-environment-variable :not-a-function "NAME" "value"))
    (signals
      type-error
      (call-with-environment-variable
        (lambda ()
          nil)
        :not-a-string
        "value"))
    (signals
      type-error
      (call-with-environment-variable
        (lambda ()
          nil)
        "NAME"
        :not-a-string))))

(describe
  "call-with-environment-variables"
  (it
    "validates every binding before changing the environment"
    (let ((name "CL_HOST_KIT_SCOPED_ENV_VALIDATE_TEST"))
      (unwind-protect (progn
          (setf (getenv name) "before")
          (signals
            type-error
            (call-with-environment-variables
              (lambda ()
                nil)
              (list (list name "after") (list "missing-value"))))
          (signals
            type-error
            (call-with-environment-variables
              (lambda ()
                nil)
              (list (list name "after") (list "" "invalid"))))
          (signals
            type-error
            (call-with-environment-variables
              (lambda ()
                nil)
              (list (list name "after") (list name "duplicate"))))
          (expect (getenv name) :to-equal "before"))
        (setf (getenv name) nil))))
  (it
    "rejects circular bindings before changing the environment"
    (let ((name "CL_HOST_KIT_SCOPED_ENV_CIRCULAR_TEST"))
      (unwind-protect (progn
          (setf (getenv name) "before")
          (let ((bindings (list (list name "after"))))
            (setf (cdr bindings) bindings)
            (unwind-protect (let ((signalled-p nil))
                (handler-case (call-with-environment-variables
                    (lambda ()
                      nil)
                    bindings)
                  (type-error ()
                    (setf signalled-p t)))
                (expect signalled-p :to-be-truthy))
              (setf (cdr bindings) nil))
            (expect (getenv name) :to-equal "before"))
          (let ((binding (list name "after")))
            (setf (cdr binding) binding)
            (unwind-protect (let ((signalled-p nil))
                (handler-case (call-with-environment-variables
                    (lambda ()
                      nil)
                    (list binding))
                  (type-error ()
                    (setf signalled-p t)))
                (expect signalled-p :to-be-truthy))
              (setf (cdr binding) nil))
            (expect (getenv name) :to-equal "before")))
        (setf (getenv name) nil))))
  (it
    "restores every binding after a callback error"
    (let ((first-name "CL_HOST_KIT_SCOPED_ENV_RESTORE_FIRST_TEST")
          (second-name "CL_HOST_KIT_SCOPED_ENV_RESTORE_SECOND_TEST"))
      (unwind-protect (progn
          (setf (getenv first-name) "first-before")
          (setf (getenv second-name) "second-before")
          (handler-case (call-with-environment-variables
              (lambda ()
                (expect (getenv first-name) :to-equal "first-temporary")
                (expect (getenv second-name) :to-equal "second-temporary")
                (error "expected test failure"))
              (list (list first-name "first-temporary") (list second-name "second-temporary")))
            (error ()
              nil))
          (expect (getenv first-name) :to-equal "first-before")
          (expect (getenv second-name) :to-equal "second-before"))
        (setf (getenv first-name) nil)
        (setf (getenv second-name) nil))))
  (it
    "supports nested scopes without prematurely restoring outer values"
    (let ((name "CL_HOST_KIT_SCOPED_ENV_NESTED_TEST"))
      (unwind-protect (progn
          (setf (getenv name) "before")
          (call-with-environment-variables
            (lambda ()
              (expect (getenv name) :to-equal "outer")
              (call-with-environment-variable
                (lambda ()
                  (expect (getenv name) :to-equal "inner"))
                name
                "inner")
              (expect (getenv name) :to-equal "outer"))
            (list (list name "outer")))
          (expect (getenv name) :to-equal "before"))
        (setf (getenv name) nil)))))

(describe
  "with-environment-variable"
  (it
    "evaluates its body with a temporary value"
    (let ((name "CL_HOST_KIT_SCOPED_ENV_MACRO_TEST"))
      (unwind-protect (progn
          (setf (getenv name) nil)
          (expect
            (with-environment-variable (name "temporary") (getenv name))
            :to-equal
            "temporary")
          (expect (getenv name) :to-be nil))
        (setf (getenv name) nil)))))

(describe
  "with-environment-variables"
  (it
    "evaluates dynamic bindings in one temporary scope"
    (let ((first-name "CL_HOST_KIT_SCOPED_ENV_BATCH_MACRO_FIRST_TEST")
          (second-name "CL_HOST_KIT_SCOPED_ENV_BATCH_MACRO_SECOND_TEST"))
      (unwind-protect (progn
          (setf (getenv first-name) nil)
          (setf (getenv second-name) nil)
          (expect
            (with-environment-variables
              ((first-name "first") (second-name "second"))
              (list (getenv first-name) (getenv second-name)))
            :to-equal
            (list "first" "second"))
          (expect (getenv first-name) :to-be nil)
          (expect (getenv second-name) :to-be nil))
        (setf (getenv first-name) nil)
        (setf (getenv second-name) nil))))
  (it
    "rejects malformed bindings during macro expansion"
    (signals
      error
      (macroexpand-1
        (quote (with-environment-variables ((name "value" "extra")) nil))))))

(describe
  "command-line-arguments"
  (it
    "omits the executable name and returns a fresh list"
    (let ((sb-ext:*posix-argv* '("host-kit" "compile" "input.lisp")))
      (let ((arguments (command-line-arguments)))
        (expect arguments :to-equal '("compile" "input.lisp"))
        (setf (first arguments) "changed")
        (expect (command-line-arguments) :to-equal '("compile" "input.lisp"))))))

(progn
  (describe
    "hostname"
    (it
      "returns a non-empty host name string"
      (let ((name (hostname)))
        (expect (stringp name) :to-be-truthy)
        (expect (plusp (length name)) :to-be-truthy))))
  (describe
    "process identity"
    (it
      "returns non-negative Unix IDs that match SB-POSIX"
      (dolist (entry
          (list
            (list (user-id) (sb-posix:getuid))
            (list (group-id) (sb-posix:getgid))
            (list (effective-user-id) (sb-posix:geteuid))
            (list (effective-group-id) (sb-posix:getegid))))
        (expect (first entry) :to-equal (second entry))
        (expect (typep (first entry) (quote (integer 0 *))) :to-be-truthy)))
    (it
      "resolves process identities to their passwd and group names"
      (dolist (entry
          (list
            (list (user-name) (sb-posix:passwd-name (sb-posix:getpwuid (sb-posix:getuid))))
            (list (group-name) (sb-posix:group-name (sb-posix:getgrgid (sb-posix:getgid))))
            (list
              (effective-user-name)
              (sb-posix:passwd-name (sb-posix:getpwuid (sb-posix:geteuid))))
            (list
              (effective-group-name)
              (sb-posix:group-name (sb-posix:getgrgid (sb-posix:getegid))))))
        (expect (first entry) :to-equal (second entry))
        (expect (stringp (first entry)) :to-be-truthy)
        (expect (plusp (length (first entry))) :to-be-truthy)))
    (it
      "normalizes missing passwd and group records"
      (signals host-operation-failed (host-kit::%passwd-name 2147483647 :user-name))
      (signals host-operation-failed (host-kit::%group-name 2147483647 :group-name)))))

(describe
  "user directories"
  (it
    "uses HOME and standard XDG fallback locations"
    (with-environment-variables
      (("HOME" "/tmp/cl-host-kit-home/")
        ("XDG_CONFIG_HOME" nil)
        ("XDG_DATA_HOME" nil)
        ("XDG_CACHE_HOME" nil)
        ("XDG_STATE_HOME" nil))
      (expect (namestring (user-home-directory)) :to-equal "/tmp/cl-host-kit-home/")
      (expect
        (namestring (user-config-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.config/")
      (expect
        (namestring (user-data-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.local/share/")
      (expect
        (namestring (user-cache-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.cache/")
      (expect
        (namestring (user-state-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.local/state/")))
  (it
    "uses absolute XDG overrides"
    (with-environment-variables
      (("XDG_CONFIG_HOME" "/tmp/cl-host-kit-config/")
        ("XDG_DATA_HOME" "/tmp/cl-host-kit-data/")
        ("XDG_CACHE_HOME" "/tmp/cl-host-kit-cache/")
        ("XDG_STATE_HOME" "/tmp/cl-host-kit-state/")
        ("XDG_RUNTIME_DIR" "/tmp/cl-host-kit-runtime/"))
      (expect
        (namestring (user-config-directory))
        :to-equal
        "/tmp/cl-host-kit-config/")
      (expect (namestring (user-data-directory)) :to-equal "/tmp/cl-host-kit-data/")
      (expect (namestring (user-cache-directory)) :to-equal "/tmp/cl-host-kit-cache/")
      (expect (namestring (user-state-directory)) :to-equal "/tmp/cl-host-kit-state/")
      (expect
        (namestring (user-runtime-directory))
        :to-equal
        "/tmp/cl-host-kit-runtime/")))
  (it
    "ignores relative XDG locations and has no runtime fallback"
    (with-environment-variables
      (("HOME" "/tmp/cl-host-kit-home/")
        ("XDG_CONFIG_HOME" "relative-config")
        ("XDG_RUNTIME_DIR" "relative-runtime"))
      (expect
        (namestring (user-config-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.config/")
      (expect (user-runtime-directory) :to-be nil)))
  (it
    "ignores empty XDG locations and has no runtime fallback"
    (with-environment-variables
      (("HOME" "/tmp/cl-host-kit-home/")
        ("XDG_CONFIG_HOME" "")
        ("XDG_DATA_HOME" "")
        ("XDG_CACHE_HOME" "")
        ("XDG_STATE_HOME" "")
        ("XDG_RUNTIME_DIR" ""))
      (expect
        (namestring (user-config-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.config/")
      (expect
        (namestring (user-data-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.local/share/")
      (expect
        (namestring (user-cache-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.cache/")
      (expect
        (namestring (user-state-directory))
        :to-equal
        "/tmp/cl-host-kit-home/.local/state/")
      (expect (user-runtime-directory) :to-be nil)))
  (it
    "falls back to the passwd home directory when HOME is unavailable"
    (with-environment-variable
      ("HOME" nil)
      (let ((directory (user-home-directory)))
        (expect (directory-pathname-p directory) :to-be-truthy)
        (expect (absolute-pathname-p directory) :to-be-truthy)))))

(describe
  "quit"
  (it
    "terminates a child SBCL with the supplied code"
    (let* ((source-directory (asdf:system-source-directory "cl-host-kit"))
           (source-files
          (mapcar
            (lambda (file)
              (namestring (merge-pathnames file source-directory)))
            '("src/package.lisp" "src/conditions.lisp" "src/environment.lisp")))
           (form
          (format
            nil
            "(progn ~{(load ~S)~} (funcall (find-symbol \"QUIT\" \"HOST-KIT\") 23))"
            source-files))
           (process
          (sb-ext:run-program
            (namestring sb-ext:*runtime-pathname*)
            (list "--noinform" "--non-interactive" "--eval" form)
            :search
            nil
            :wait
            t
            :output
            nil
            :error
            nil)))
      (expect (sb-ext:process-exit-code process) :to-equal 23))))
