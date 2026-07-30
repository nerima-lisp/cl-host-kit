;;;; src/environment.lisp
;;;;
;;;; Environment-variable access, process/user identity, and process
;;;; termination for SBCL.
(in-package #:host-kit)

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

(defvar *environment-scope-lock*
  (sb-thread:make-mutex :name "host-kit environment scope"))

(defvar *environment-scope-lock-held-p* nil)

(defun %call-with-environment-scope-lock (thunk)
  (if *environment-scope-lock-held-p*
      (funcall thunk)
      (sb-thread:with-mutex (*environment-scope-lock*)
        (let ((*environment-scope-lock-held-p* t))
          (funcall thunk)))))

(defun getenv (name)
  "Return the value of environment variable NAME as a string, or NIL if it is
unset."
  (%check-environment-variable-name name)
  (sb-posix:getenv name))

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

(defun environment-variables ()
  "Return a fresh snapshot of the process environment as NAME=VALUE strings.
The result can be passed directly to RUN-PROGRAM's :ENVIRONMENT option.
Mutating the returned list or its strings cannot change the process environment."
  (mapcar #'copy-seq (sb-ext:posix-environ)))

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

(defun command-line-arguments ()
  "Return a fresh list of arguments passed to the current program.
The executable name is omitted."
  (copy-list (cdr sb-ext:*posix-argv*)))

(defun hostname ()
  "Return the host name reported by the Common Lisp implementation."
  (machine-instance))

(defun user-id ()
  "Return the real Unix user ID of the current process."
  (sb-posix:getuid))

(defun group-id ()
  "Return the real Unix group ID of the current process."
  (sb-posix:getgid))

(defun effective-user-id ()
  "Return the effective Unix user ID of the current process."
  (sb-posix:geteuid))

(defun effective-group-id ()
  "Return the effective Unix group ID of the current process."
  (sb-posix:getegid))

(defun %passwd-name (id operation)
  (%with-host-operation (operation id)
    (let ((entry (sb-posix:getpwuid id)))
      (unless entry
        (error "No passwd entry exists for user ID ~D." id))
      (copy-seq (sb-posix:passwd-name entry)))))

(defun %group-name (id operation)
  (%with-host-operation (operation id)
    (let ((entry (sb-posix:getgrgid id)))
      (unless entry
        (error "No group entry exists for group ID ~D." id))
      (copy-seq (sb-posix:group-name entry)))))

(defun user-name ()
  "Return the passwd name for the real Unix user ID of the current process."
  (%passwd-name (user-id) :user-name))

(defun group-name ()
  "Return the group name for the real Unix group ID of the current process."
  (%group-name (group-id) :group-name))

(defun effective-user-name ()
  "Return the passwd name for the effective Unix user ID of the current process."
  (%passwd-name (effective-user-id) :effective-user-name))

(defun effective-group-name ()
  "Return the group name for the effective Unix group ID of the current process."
  (%group-name (effective-group-id) :effective-group-name))

(defun quit (&optional (code 0))
  "Terminate the current process with CODE (default 0), the HOST-KIT
equivalent of a modern language's os.exit()/process.exit(). Never returns."
  (sb-ext:exit :code code :abort nil))

(defun %passwd-home-directory ()
  (%with-host-operation (:user-home-directory nil)
    (let ((entry (sb-posix:getpwuid (effective-user-id))))
      (unless entry
        (error "Unable to find a passwd entry for the effective user."))
      (ensure-directory-pathname (ensure-absolute-pathname (sb-posix:passwd-dir entry))))))

(defun user-home-directory ()
  "Return the current user home directory as an absolute directory pathname.
Use HOME when it is non-empty; otherwise use the effective user passwd entry."
  (let ((home (getenv "HOME")))
    (if (and home (plusp (length home)))
        (ensure-directory-pathname (ensure-absolute-pathname home))
        (%passwd-home-directory))))

(defun %absolute-environment-directory (environment-variable)
  (let ((value (getenv environment-variable)))
    (and value
         (plusp (length value))
         (absolute-pathname-p value)
         (ensure-directory-pathname value))))

(defun %xdg-directory (environment-variable fallback)
  (or (%absolute-environment-directory environment-variable) fallback))

(defun user-config-directory ()
  "Return XDG_CONFIG_HOME, or the default ~/.config/ directory.
Relative and empty XDG_CONFIG_HOME values are ignored."
  (%xdg-directory "XDG_CONFIG_HOME"
                  (merge-pathnames ".config/" (user-home-directory))))

(defun user-data-directory ()
  "Return XDG_DATA_HOME, or the default ~/.local/share/ directory.
Relative and empty XDG_DATA_HOME values are ignored."
  (%xdg-directory "XDG_DATA_HOME"
                  (merge-pathnames ".local/share/" (user-home-directory))))

(defun user-cache-directory ()
  "Return XDG_CACHE_HOME, or the default ~/.cache/ directory.
Relative and empty XDG_CACHE_HOME values are ignored."
  (%xdg-directory "XDG_CACHE_HOME"
                  (merge-pathnames ".cache/" (user-home-directory))))

(defun user-state-directory ()
  "Return XDG_STATE_HOME, or the default ~/.local/state/ directory.
Relative and empty XDG_STATE_HOME values are ignored."
  (%xdg-directory "XDG_STATE_HOME"
                  (merge-pathnames ".local/state/" (user-home-directory))))

(defun user-runtime-directory ()
  "Return absolute XDG_RUNTIME_DIR as a directory pathname, or NIL.
NIL is returned when XDG_RUNTIME_DIR is unset, empty, or relative."
  (%absolute-environment-directory "XDG_RUNTIME_DIR"))
