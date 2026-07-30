;;;; src/environment.lisp
;;;;
;;;; Environment-variable access and process termination. Every top-level
;;;; form is individually feature-gated (#+sbcl / #-sbcl), following
;;;; cl-tty-kit's precedent: the #-sbcl branch of each function still exists
;;;; and calls %UNSUPPORTED, so the public API is identical across
;;;; implementations and a non-SBCL caller gets a structured condition
;;;; instead of an undefined-function error.
(in-package #:host-kit)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun %environment-variable-name-p (value)
  (and
    (stringp value)
    (plusp (length value))
    (not (find #\= value))
    (not (find #\Null value))))

(defun %check-environment-variable-name (name)
  (unless (%environment-variable-name-p name)
    (error 'type-error :datum name :expected-type 'string))
  name)

(defun %check-environment-variable-value (value)
  (check-type value (or null string))
  (when (and value (find #\Null value))
    (error 'type-error :datum value :expected-type '(or null string)))
  value)

(progn
  (defun %validate-environment-binding (binding)
    (unless (and (listp binding) (eql (list-length binding) 2))
      (error 'type-error :datum binding :expected-type 'list))
    (destructuring-bind (name value) binding
      (list
        (%check-environment-variable-name name)
        (%check-environment-variable-value value))))
  (defun %validate-environment-bindings (bindings)
    (check-type bindings list)
    (unless (list-length bindings)
      (error 'type-error :datum bindings :expected-type 'list))
    (loop with names = '()
          for binding in bindings
          for normalized = (%validate-environment-binding binding)
          for name = (first normalized)
          do (when (find name names :test #'string=)
        (error 'type-error :datum bindings :expected-type 'list)) (push name names)
          collect normalized))
  (defun %save-environment-bindings (bindings)
    (mapcar
      (lambda (binding)
        (list (first binding) (getenv (first binding))))
      bindings))
  (defun %install-environment-bindings (bindings)
    (dolist (binding bindings)
      (setf (getenv (first binding)) (second binding))))
  (defun %restore-environment-bindings (bindings)
    (dolist (binding (reverse bindings))
      (setf (getenv (first binding)) (second binding)))))

#+sbcl
(defvar *environment-scope-lock*
  (sb-thread:make-mutex :name "host-kit environment scope"))

#+sbcl
(defvar *environment-scope-lock-held-p* nil)

#+sbcl
(defun %call-with-environment-scope-lock (thunk)
  (if *environment-scope-lock-held-p*
      (funcall thunk)
      (sb-thread:with-mutex (*environment-scope-lock*)
        (let ((*environment-scope-lock-held-p* t))
          (funcall thunk)))))

#-sbcl
(defun %call-with-environment-scope-lock (thunk)
  (funcall thunk))

#+sbcl
(defun getenv (name)
  "Return the value of environment variable NAME as a string, or NIL if it is
unset."
  (%check-environment-variable-name name)
  (sb-posix:getenv name))

#-sbcl
(defun getenv (name)
  (declare (ignore name))
  (%unsupported 'getenv))

#+sbcl
(defun (setf getenv) (value name)
  "Set environment variable NAME to VALUE (a string). A VALUE of NIL unsets
NAME instead."
  (%check-environment-variable-name name)
  (%check-environment-variable-value value)
  (%call-with-environment-scope-lock
   (lambda ()
     (%with-host-operation (:setf-getenv name)
       (if value
           (sb-posix:setenv name value 1)
           (sb-posix:unsetenv name)))))
  value)

#-sbcl
(defun (setf getenv) (value name)
  (declare (ignore value name))
  (%unsupported 'getenv))

#+sbcl
(defun environment-variables ()
  "Return a fresh snapshot of the process environment as NAME=VALUE strings.
The result can be passed directly to RUN-PROGRAM's :ENVIRONMENT option.
Mutating the returned list or its strings cannot change the process environment."
  (mapcar #'copy-seq (sb-ext:posix-environ)))

#-sbcl
(defun environment-variables ()
  (%unsupported 'environment-variables))

(defun call-with-environment-variables (thunk bindings)
  "Call THUNK with every (NAME VALUE) pair in BINDINGS temporarily installed.

VALUE is a string or NIL; NIL temporarily unsets NAME. All bindings are
validated before the process environment changes, duplicate names are rejected,
and every prior value is restored on every exit path. THUNK receives no
arguments and its values are returned. Scoped changes are serialized with other
HOST-KIT environment writes."
  (check-type thunk function)
  (let ((bindings (%validate-environment-bindings bindings)))
    (%call-with-environment-scope-lock
      (lambda ()
        (let ((previous-bindings (%save-environment-bindings bindings)))
          (unwind-protect (progn
              (%install-environment-bindings bindings)
              (funcall thunk))
            (%restore-environment-bindings previous-bindings)))))))

(defun call-with-environment-variable (thunk name value)
  "Call THUNK with environment variable NAME temporarily set to VALUE.

VALUE is a string or NIL; NIL temporarily unsets NAME. The previous value is
restored when THUNK returns or exits non-locally. THUNK receives no arguments
and its values are returned."
  (call-with-environment-variables thunk (list (list name value))))

(defmacro with-environment-variable ((name value) &body body)
  "Evaluate BODY with environment variable NAME temporarily set to VALUE."
  `(call-with-environment-variable
    (lambda ()
      ,@body)
    ,name
    ,value))

(defmacro with-environment-variables ((&rest bindings) &body body)
  "Evaluate BODY with each (NAME VALUE) binding temporarily installed."
  (dolist (binding bindings)
    (unless (and (listp binding) (= (length binding) 2))
      (error "Each environment binding must have a name and value: ~S" binding)))
  `(call-with-environment-variables
    (lambda ()
      ,@body)
    (list
      ,@(mapcar
        (lambda (binding)
          `(list ,@binding))
        bindings))))

#+sbcl
(defun command-line-arguments ()
  "Return a fresh list of arguments passed to the current program.
The executable name is omitted."
  (copy-list (cdr sb-ext:*posix-argv*)))

#-sbcl
(defun command-line-arguments ()
  (%unsupported 'command-line-arguments))

(defun hostname ()
  "Return the host name reported by the Common Lisp implementation."
  (machine-instance))

#+sbcl
  (defun user-id ()
    "Return the real Unix user ID of the current process."
    (sb-posix:getuid))

#-sbcl
  (defun user-id ()
    (%unsupported (quote user-id)))

#+sbcl
  (defun group-id ()
    "Return the real Unix group ID of the current process."
    (sb-posix:getgid))

#-sbcl
  (defun group-id ()
    (%unsupported (quote group-id)))

#+sbcl
  (defun effective-user-id ()
    "Return the effective Unix user ID of the current process."
    (sb-posix:geteuid))

#-sbcl
  (defun effective-user-id ()
    (%unsupported (quote effective-user-id)))

#+sbcl
  (defun effective-group-id ()
    "Return the effective Unix group ID of the current process."
    (sb-posix:getegid))

#-sbcl
  (defun effective-group-id ()
    (%unsupported (quote effective-group-id)))

#+sbcl
  (defun %passwd-name (id operation)
    (%with-host-operation (operation id)
      (let ((entry (sb-posix:getpwuid id)))
        (unless entry
          (error "No passwd entry exists for user ID ~D." id))
        (copy-seq (sb-posix:passwd-name entry)))))

#+sbcl
  (defun %group-name (id operation)
    (%with-host-operation (operation id)
      (let ((entry (sb-posix:getgrgid id)))
        (unless entry
          (error "No group entry exists for group ID ~D." id))
        (copy-seq (sb-posix:group-name entry)))))

#+sbcl
  (defun user-name ()
    "Return the passwd name for the real Unix user ID of the current process."
    (%passwd-name (user-id) :user-name))

#-sbcl
  (defun user-name ()
    (%unsupported (quote user-name)))

#+sbcl
  (defun group-name ()
    "Return the group name for the real Unix group ID of the current process."
    (%group-name (group-id) :group-name))

#-sbcl
  (defun group-name ()
    (%unsupported (quote group-name)))

#+sbcl
  (defun effective-user-name ()
    "Return the passwd name for the effective Unix user ID of the current process."
    (%passwd-name (effective-user-id) :effective-user-name))

#-sbcl
  (defun effective-user-name ()
    (%unsupported (quote effective-user-name)))

#+sbcl
  (defun effective-group-name ()
    "Return the group name for the effective Unix group ID of the current process."
    (%group-name (effective-group-id) :effective-group-name))

#-sbcl
  (defun effective-group-name ()
    (%unsupported (quote effective-group-name)))

#+sbcl
(defun quit (&optional (code 0))
  "Terminate the current process with CODE (default 0), the HOST-KIT
equivalent of a modern language's os.exit()/process.exit(). Never returns."
  (sb-ext:exit :code code :abort nil))

#-sbcl
(defun quit (&optional (code 0))
  (declare (ignore code))
  (%unsupported 'quit))

#+sbcl (defun %passwd-home-directory () (%with-host-operation (:user-home-directory nil) (let ((entry (sb-posix:getpwuid (effective-user-id)))) (unless entry (error "Unable to find a passwd entry for the effective user.")) (ensure-directory-pathname (ensure-absolute-pathname (sb-posix:passwd-dir entry))))))

#+sbcl
(defun user-home-directory ()
  "Return the current user home directory as an absolute directory pathname.
Use HOME when it is non-empty; otherwise use the effective user passwd entry."
  (let ((home (getenv "HOME")))
    (if (and home (plusp (length home)))
        (ensure-directory-pathname (ensure-absolute-pathname home))
        (%passwd-home-directory))))

#+sbcl
(defun %absolute-environment-directory (environment-variable)
  (let ((value (getenv environment-variable)))
    (and value
         (plusp (length value))
         (absolute-pathname-p value)
         (ensure-directory-pathname value))))

#+sbcl
(defun %xdg-directory (environment-variable fallback)
  (or (%absolute-environment-directory environment-variable) fallback))

#+sbcl
(defun user-config-directory ()
  "Return XDG_CONFIG_HOME, or the default ~/.config/ directory.
Relative and empty XDG_CONFIG_HOME values are ignored."
  (%xdg-directory "XDG_CONFIG_HOME"
                  (merge-pathnames ".config/" (user-home-directory))))

#+sbcl
(defun user-data-directory ()
  "Return XDG_DATA_HOME, or the default ~/.local/share/ directory.
Relative and empty XDG_DATA_HOME values are ignored."
  (%xdg-directory "XDG_DATA_HOME"
                  (merge-pathnames ".local/share/" (user-home-directory))))

#+sbcl
(defun user-cache-directory ()
  "Return XDG_CACHE_HOME, or the default ~/.cache/ directory.
Relative and empty XDG_CACHE_HOME values are ignored."
  (%xdg-directory "XDG_CACHE_HOME"
                  (merge-pathnames ".cache/" (user-home-directory))))

#+sbcl
(defun user-state-directory ()
  "Return XDG_STATE_HOME, or the default ~/.local/state/ directory.
Relative and empty XDG_STATE_HOME values are ignored."
  (%xdg-directory "XDG_STATE_HOME"
                  (merge-pathnames ".local/state/" (user-home-directory))))

#+sbcl
(defun user-runtime-directory ()
  "Return absolute XDG_RUNTIME_DIR as a directory pathname, or NIL.
NIL is returned when XDG_RUNTIME_DIR is unset, empty, or relative."
  (%absolute-environment-directory "XDG_RUNTIME_DIR"))

#-sbcl
(progn
  (defun user-home-directory ()
    (%unsupported (quote user-home-directory)))
  (defun user-config-directory ()
    (%unsupported (quote user-config-directory)))
  (defun user-data-directory ()
    (%unsupported (quote user-data-directory)))
  (defun user-cache-directory ()
    (%unsupported (quote user-cache-directory)))
  (defun user-state-directory ()
    (%unsupported (quote user-state-directory)))
  (defun user-runtime-directory ()
    (%unsupported (quote user-runtime-directory))))
