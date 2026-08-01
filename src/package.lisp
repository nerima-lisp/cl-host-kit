;;;; src/package.lisp
;;;;
;;;; The single public package. Every symbol a caller needs -- environment
;;;; variables, the working directory, pathname coercion/predicates,
;;;; filesystem queries, direct program execution, and string helpers -- is
;;;; exported here and nothing else.
(defpackage #:host-kit
  (:use #:cl)
  (:export
   ;; Conditions
   #:host-kit-error
   #:host-operation-failed
   #:host-operation-failed-operation
   #:host-operation-failed-target
   #:host-operation-failed-reason
   #:process-timeout
   #:process-timeout-program
   #:process-timeout-arguments
   #:process-timeout-seconds
   #:process-timeout-result
   #:file-lock-timeout
   #:file-lock-timeout-seconds
   #:process-exit-error
   #:process-exit-error-program
   #:process-exit-error-arguments
   #:process-exit-error-exit-code
   #:process-exit-error-signal
   #:process-exit-error-expected-exit-codes
   #:process-exit-error-result
   ;; Environment and process lifecycle
   #:getenv
   #:environment-variables
   #:call-with-environment-variables
   #:with-environment-variables
   #:call-with-environment-variable
   #:with-environment-variable
   #:quit
   #:command-line-arguments
   #:hostname
   #:user-id
   #:group-id
   #:effective-user-id
   #:effective-group-id
   #:user-name
   #:group-name
   #:effective-user-name
   #:effective-group-name
   #:user-home-directory
   #:user-config-directory
   #:user-data-directory
   #:user-cache-directory
   #:user-state-directory
   #:user-runtime-directory
   ;; Program execution
   #:+default-command-timeout-seconds+
   #:+default-command-output-limit+
   #:process-result
   #:process-result-program
   #:process-result-arguments
   #:process-result-exit-code
   #:process-result-signal
   #:process-result-stdout
   #:process-result-stderr
   #:process-result-timed-out-p
   #:process-result-stdout-truncated-p
   #:process-result-stderr-truncated-p
   #:find-program
   #:run-program
   #:ensure-program-success
   #:call-with-program-result
   #:with-program-result
   #:call-with-program-output #:with-program-output
   #:call-with-program-input #:with-program-input
   #:call-with-program-io #:with-program-io
   ;; Working directory
   #:getcwd
   #:chdir
   #:call-with-working-directory
   #:with-working-directory
   ;; Pathname coercion and predicates
   #:absolute-pathname-p
   #:directory-pathname-p
   #:ensure-directory-pathname
   #:ensure-pathname
   #:ensure-absolute-pathname
   #:pathname-directory-pathname
   #:parent-directory-pathname
   #:truenamize #:pathname-within-p #:relative-pathname
   ;; Filesystem queries and mutation
   #:file-metadata
   #:file-metadata-p
   #:file-metadata-kind
   #:file-metadata-size
   #:file-metadata-modification-time
   #:file-metadata-access-time
   #:file-metadata-change-time
   #:file-metadata-mode
   #:file-metadata-device
   #:file-metadata-inode
   #:file-metadata-hard-link-count
   #:file-metadata-owner-id
   #:file-metadata-group-id
   #:symbolic-link-p
   #:read-symbolic-link
   #:create-symbolic-link
   #:create-hard-link
   #:set-file-mode #:set-file-owner
   #:set-file-times #:touch-file
   #:path-exists-p #:file-exists-p
   #:directory-exists-p
   #:create-directory #:same-file-p
   #:directory-empty-p
   #:file-readable-p
   #:file-writable-p
   #:file-executable-p
   #:directory-files
   #:subdirectories
   #:call-with-directory-entries
   #:with-directory-entries
   #:call-with-directory-tree
   #:with-directory-tree
   #:ensure-directory-tree
   #:delete-file-if-exists
   #:delete-empty-directory
   #:delete-path
   #:delete-directory-tree
   #:move-path
   #:temporary-directory
   #:call-with-temporary-directory
   #:with-temporary-directory
   #:call-with-temporary-file
   #:with-temporary-file
   #:read-file-string
   #:call-with-file-string-chunks
   #:with-file-string-chunks
   #:read-file-lines
   #:call-with-file-lines
   #:with-file-lines
   #:read-file-octets
   #:call-with-file-octet-chunks
   #:with-file-octet-chunks
   #:write-file-string
   #:write-file-lines
   #:write-file-octets
   #:copy-file
   #:copy-directory-tree
   #:copy-path
   #:call-with-atomic-output-file
   #:with-atomic-output-file
   #:call-with-advisory-file-lock
   #:with-advisory-file-lock
   #:call-with-file-lock
   #:with-file-lock
   ;; Strings
   #:split-string
   #:string-prefix-p #:string-suffix-p #:join-strings
   ;; Dispatch
   #:symbol-call))
