;;;; src/temporary-resources.lisp
;;;;
;;;; Scoped temporary files and directories.  Public entry points use CPS so
;;;; cleanup follows the dynamic extent even when the caller signals.
(in-package #:host-kit)

(defun temporary-directory ()
  "Return the system temporary directory as an absolute directory pathname,
honoring a non-empty absolute TMPDIR and falling back to /tmp/ otherwise."
  (let ((configured-directory (getenv "TMPDIR")))
    (ensure-absolute-pathname
     (ensure-directory-pathname
      (if (and configured-directory
               (plusp (length configured-directory))
               (absolute-pathname-p configured-directory))
          configured-directory
          "/tmp/")))))

(defun %validate-temporary-name-fragment (fragment argument)
  "Reject path separators and NUL in a temporary resource name component."
  (declare (ignore argument))
  (when (or (find #\/ fragment) (find #\Null fragment))
    (error 'type-error :datum fragment :expected-type 'string))
  fragment)

(defun %temporary-template (directory prefix)
  "Return an SB-POSIX secure temporary-name template beneath DIRECTORY."
  (namestring (merge-pathnames (format nil "~AXXXXXX" prefix) directory)))

(defun %name-collision-p (condition)
  (= (sb-posix:syscall-errno condition) sb-posix:eexist))

(defun %create-temporary-directory (directory prefix)
  "Create an owner-only directory with an OS-generated unpredictable name."
  (handler-case
      (ensure-directory-pathname
       (sb-posix:mkdtemp (%temporary-template directory prefix)))
    (sb-posix:syscall-error (condition)
      (if (%name-collision-p condition)
          nil
          (error condition)))))

(defun %temporary-resource-keep-p (keep)
    (if (functionp keep)
        (funcall keep)
        keep))
  (defun %temporary-resource-parent (directory)
    (ensure-directory-pathname (or directory (temporary-directory))))

  (defun %validate-temporary-directory-options (thunk prefix attempts)
  "Validate the public temporary-directory lifecycle options."
  (check-type thunk function)
  (check-type prefix string)
  (check-type attempts (integer 1 *))
  (%validate-temporary-name-fragment prefix 'prefix))

  (defun %create-temporary-directory-with-retry (parent prefix attempts)
    "Create a temporary directory below PARENT, retrying name collisions."
    (loop repeat attempts
          for created = (%create-temporary-directory parent prefix)
          when created
            do (return created)
          finally
             (error "Unable to create a temporary directory after ~D attempts."
                    attempts)))

  (defun %call-with-created-temporary-directory (thunk directory keep)
    "Run THUNK for DIRECTORY and delete it unless KEEP evaluates true."
    (let ((keep-p nil))
      (unwind-protect
          (multiple-value-prog1
              (funcall thunk directory)
            (setf keep-p (%temporary-resource-keep-p keep)))
        (unless keep-p
          (ignore-errors
            (delete-directory-tree directory :if-does-not-exist :ignore))))))

(defun call-with-temporary-directory (thunk &key directory (prefix "tmp-") keep (attempts 128))
  "Call THUNK with a freshly-created private temporary directory pathname.
Delete it after normal return or signalling unless KEEP is true after success."
  (%validate-temporary-directory-options thunk prefix attempts)
  (let ((parent (%temporary-resource-parent directory)))
    (%with-host-operation
      (:call-with-temporary-directory parent)
      (%call-with-created-temporary-directory
       thunk
       (%create-temporary-directory-with-retry parent prefix attempts)
       keep))))

(defmacro with-temporary-directory ((pathname &key directory (prefix "tmp-") keep (attempts 128)) &body body)
  "Evaluate BODY with PATHNAME bound to a scoped temporary directory."
  (unless (and (symbolp pathname) (not (constantp pathname)))
    (error "PATHNAME must be a non-constant symbol: ~S" pathname))
  `(call-with-temporary-directory
    (lambda (,pathname)
      ,@body)
    :directory
    ,directory
    :prefix
    ,prefix
    :keep
    (lambda ()
      ,keep)
    :attempts
    ,attempts))

(defun %temporary-file-pathname (template suffix)
  (pathname (concatenate 'string template suffix)))

(defun %open-temporary-file (directory prefix suffix direction element-type external-format)
  "Open a securely-created temporary file, or return NIL on final-name collision."
  (let ((pathname nil))
    (handler-case
        (multiple-value-bind (fd template)
            (sb-posix:mkstemp (%temporary-template directory prefix))
          (let ((template-needs-cleanup-p t)
                (pathname-needs-cleanup-p nil))
            (setf pathname (%temporary-file-pathname template suffix))
            (unwind-protect
                 (progn
                   (unless (string= suffix "")
                     (sb-posix:link template (namestring pathname))
                     (setf pathname-needs-cleanup-p t)
                     (sb-posix:unlink template)
                     (setf template-needs-cleanup-p nil))
                   (let ((stream
                           (sb-sys:make-fd-stream
                            fd
                            :input (member direction '(:input :io))
                            :output (member direction '(:output :io))
                            :element-type element-type
                            :external-format external-format
                            :pathname pathname
                            :auto-close t)))
                     (setf fd nil
                           pathname-needs-cleanup-p nil)
                     (values stream pathname)))
              (when fd
                (ignore-errors (sb-posix:close fd)))
              (when template-needs-cleanup-p
                (ignore-errors (sb-posix:unlink template)))
              (when pathname-needs-cleanup-p
                (ignore-errors (delete-file pathname))))))
      (sb-posix:syscall-error (condition)
        (if (and pathname (probe-file pathname) (%name-collision-p condition))
            nil
            (error condition))))))

(defun %synchronize-output-stream (stream)
    "Flush STREAM and persist it when the host supports it."
    (finish-output stream)
    (sb-posix:fsync (sb-sys:fd-stream-fd stream)))
  (defun %validate-temporary-file-options
      (thunk prefix suffix attempts direction synchronize)
    "Validate the public temporary-file lifecycle options."
    (check-type thunk function)
    (check-type prefix string)
    (check-type suffix string)
    (check-type attempts (integer 1 *))
    (check-type direction (member :input :output :io))
    (check-type synchronize boolean)
    (when (and synchronize (not (member direction '(:output :io))))
      (error 'type-error
             :datum direction
             :expected-type '(member :output :io)))
    (%validate-temporary-name-fragment prefix 'prefix)
    (%validate-temporary-name-fragment suffix 'suffix))
  (defun %open-temporary-file-with-retry
      (parent prefix suffix direction element-type external-format attempts)
    "Open a temporary file below PARENT, retrying final-name collisions."
    (loop repeat attempts
          do (multiple-value-bind (stream pathname)
                 (%open-temporary-file
                  parent prefix suffix direction element-type external-format)
               (when stream
                 (return (values stream pathname))))
          finally
             (error "Unable to create a temporary file in ~S after ~D attempts"
                    parent
                    attempts)))

  (defun %call-with-closed-temporary-file (thunk stream pathname synchronize)
    "Call THUNK and close STREAM after synchronizing successful output."
    (unwind-protect
        (multiple-value-prog1
            (funcall thunk stream pathname)
          (when synchronize
            (%synchronize-output-stream stream)))
      (close stream)))
  (defun %call-with-open-temporary-file (thunk stream pathname keep synchronize)
    "Run THUNK for an open file and delete it unless KEEP evaluates true."
    (let ((keep-p nil))
      (unwind-protect
          (multiple-value-prog1
              (%call-with-closed-temporary-file thunk stream pathname synchronize)
            (setf keep-p (%temporary-resource-keep-p keep)))
        (unless keep-p
          (ignore-errors
            (delete-file pathname))))))

(defun call-with-temporary-file (thunk
    &key
    directory
    (prefix "tmp-")
    (suffix ".tmp")
    keep
    (direction :io)
    (element-type (quote character))
    (external-format :utf-8)
    (attempts 128)
    (synchronize nil))
  "Call THUNK with a fresh temporary file stream and pathname.
Close it and delete it after normal return or signalling unless KEEP is true
after a successful completion.  When SYNCHRONIZE is true, flush and fsync a
successfully completed output stream before it closes."
  (%validate-temporary-file-options
   thunk prefix suffix attempts direction synchronize)
  (let ((parent (%temporary-resource-parent directory)))
    (%with-host-operation
      (:call-with-temporary-file parent)
      (multiple-value-bind (stream pathname)
          (%open-temporary-file-with-retry
           parent prefix suffix direction element-type external-format attempts)
        (%call-with-open-temporary-file thunk stream pathname keep synchronize)))))

(defmacro with-temporary-file ((stream
      pathname
      &key
      directory
      (prefix "tmp-")
      (suffix ".tmp")
      keep
      (direction :io)
      (element-type ''character)
      (external-format :utf-8)
      (attempts 128)
      (synchronize nil))
    &body
    body)
  "Evaluate BODY with STREAM and PATHNAME bound to a scoped temporary file."
  (unless (and (symbolp stream) (not (constantp stream)))
    (error "STREAM must be a non-constant symbol: ~S" stream))
  (unless (and (symbolp pathname) (not (constantp pathname)))
    (error "PATHNAME must be a non-constant symbol: ~S" pathname))
  `(call-with-temporary-file
    (lambda (,stream ,pathname)
      ,@body)
    :directory
    ,directory
    :prefix
    ,prefix
    :suffix
    ,suffix
    :keep
    (lambda ()
      ,keep)
    :direction
    ,direction
    :element-type
    ,element-type
    :external-format
    ,external-format
    :attempts
    ,attempts
    :synchronize
    ,synchronize))
