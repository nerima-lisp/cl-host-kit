;;;; src/package.lisp
;;;;
;;;; The single public package. Every symbol a caller needs -- environment
;;;; variables, the working directory, pathname coercion/predicates,
;;;; filesystem queries, and the two string helpers -- is exported here and
;;;; nothing else.
(defpackage #:host-kit
  (:use #:cl)
  (:export
   ;; Conditions
   #:host-kit-error
   #:host-operation-failed
   #:host-operation-failed-operation
   #:host-operation-failed-target
   #:host-operation-failed-reason
   ;; Environment and process lifecycle
   #:getenv
   #:quit
   ;; Working directory
   #:getcwd
   #:chdir
   ;; Pathname coercion and predicates
   #:absolute-pathname-p
   #:directory-pathname-p
   #:ensure-directory-pathname
   #:ensure-pathname
   #:ensure-absolute-pathname
   #:pathname-directory-pathname
   #:truenamize
   ;; Filesystem queries and mutation
   #:file-exists-p
   #:directory-exists-p
   #:directory-files
   #:subdirectories
   #:delete-directory-tree
   #:rename-file-overwriting-target
   #:temporary-directory
   #:read-file-string
   ;; Strings
   #:split-string
   #:string-prefix-p))
