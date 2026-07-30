;;;; src/filesystem.lisp
;;;;
;;;; Existence checks, non-recursive listing, deletion, renaming, temporary
;;;; directories, and whole-file reads. Existence and listing are built on
;;;; PROBE-FILE and CL:DIRECTORY rather than raw sb-posix stat/opendir calls:
;;;; PROBE-FILE already normalizes a directory target to directory-form (with
;;;; a trailing separator, regardless of how it was spelled), which is
;;;; exactly the "truthy pathname or NIL" contract every existing call site
;;;; in the org relies on.
(in-package #:host-kit)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defun file-exists-p (pathspec)
  "Return the truename of PATHSPEC if it exists and is not a directory, else
NIL."
  (let ((truename (probe-file pathspec)))
    (and truename (not (directory-pathname-p truename)) truename)))

(defun directory-exists-p (pathspec)
  "Return the truename of PATHSPEC if it exists and is a directory, else
NIL."
  (let ((truename (probe-file pathspec)))
    (and truename (directory-pathname-p truename) truename)))

(defun directory-files (pathspec)
  "Return a list of pathnames for the regular files directly inside
directory PATHSPEC. Non-recursive: subdirectories are excluded."
  (remove-if #'directory-pathname-p
             (directory (merge-pathnames (make-pathname :name :wild :type :wild)
                                          (ensure-directory-pathname pathspec)))))

(defun subdirectories (pathspec)
  "Return a list of directory-form pathnames for the immediate subdirectories
of directory PATHSPEC. Non-recursive."
  (directory (merge-pathnames (make-pathname :directory '(:relative :wild) :name nil :type nil)
                               (ensure-directory-pathname pathspec))))

(defun delete-directory-tree (pathspec &key validate (if-does-not-exist :error))
  "Recursively delete the directory PATHSPEC. IF-DOES-NOT-EXIST is :ERROR
(the default) or :IGNORE, in which case a missing PATHSPEC is treated as
already-deleted rather than an error. VALIDATE, when true, additionally
requires PATHSPEC to be a directory-form pathname before anything is
deleted -- a guard against accidentally passing a bare file pathname."
  (%with-host-operation (:delete-directory-tree pathspec)
    (when (and validate (not (directory-pathname-p pathspec)))
      (error "~S does not denote a directory" pathspec))
    (let ((pathname (ensure-directory-pathname pathspec)))
      (handler-case (sb-ext:delete-directory pathname :recursive t)
        (file-error ()
          (unless (eq if-does-not-exist :ignore)
            (error "~S does not exist" pathname))))))
  (values))

#+sbcl
(defun rename-file-overwriting-target (source target)
  "Rename SOURCE to TARGET, atomically replacing TARGET if it already
exists. Built on POSIX rename(2) (via sb-posix:rename) rather than
CL:RENAME-FILE, since rename(2) already overwrites its destination
atomically."
  (%with-host-operation (:rename-file-overwriting-target (list source target))
    (sb-posix:rename (pathname source) (pathname target)))
  (values))

#-sbcl
(defun rename-file-overwriting-target (source target)
  (declare (ignore source target))
  (%unsupported 'rename-file-overwriting-target))

(defun temporary-directory ()
  "Return the system temporary directory as a directory-form pathname,
honoring TMPDIR when set and falling back to /tmp/ otherwise."
  (ensure-directory-pathname (or (getenv "TMPDIR") "/tmp/")))

(defun %temporary-file-keep-p (keep)
  (if (or (functionp keep)
          (and (symbolp keep) (fboundp keep)))
      (funcall keep)
      keep))

(defun %temporary-file-pathname (prefix-namestring counter suffix type)
  (pathname
   (format nil "~A~36R~@[~A~]~@[.~A~]"
           prefix-namestring counter suffix
           (unless (eq type :unspecific) type))))

(defun %open-temporary-file (pathname direction element-type external-format)
  "Open PATHNAME exclusively, returning NIL when another process owns it."
  (handler-case
      (open pathname
            :direction direction
            :element-type element-type
            :external-format external-format
            :if-exists nil
            :if-does-not-exist :create)
    (file-error (condition)
      ;; A collision is expected and retried; every other FILE-ERROR remains
      ;; an operation failure for the caller.
      (if (probe-file pathname)
          nil
          (error condition)))))

(defun call-with-temporary-file
    (thunk &key
           (want-stream-p t)
           (want-pathname-p t)
           (direction :io)
           keep
           after
           directory
           (type "tmp" typep)
           prefix
           (suffix (when typep "-tmp"))
           (element-type 'character)
           (external-format :utf-8)
           (attempts 128))
  "Create a unique temporary file, call THUNK, then delete the file by default.

THUNK receives the open stream and pathname requested by WANT-STREAM-P and
WANT-PATHNAME-P. When WANT-STREAM-P is NIL, it receives the pathname only
after the stream is closed. KEEP may be a boolean or zero-argument function;
a true value preserves the file. AFTER, when supplied, receives the closed
pathname and determines the returned values. ATTEMPTS bounds exclusive-create
retries after name collisions."
  (check-type attempts (integer 1 *))
  (let* ((directory (or directory (temporary-directory)))
         (prefix-pathname (ensure-absolute-pathname (or prefix "tmp") directory))
         (prefix-namestring (namestring prefix-pathname)))
    (loop
      :repeat attempts
      :for counter :from (random (expt 36 8))
      :for pathname = (%temporary-file-pathname prefix-namestring counter suffix type)
      :for stream =
        (%with-host-operation (:call-with-temporary-file pathname)
          (ensure-directories-exist pathname)
          (%open-temporary-file pathname direction element-type external-format))
      :when stream
        :do
           (let ((created-p t)
                 (results nil))
             (unwind-protect
                  (progn
                    (unwind-protect
                         (when (and want-stream-p thunk)
                           (setf results
                                 (multiple-value-list
                                  (if want-pathname-p
                                      (funcall thunk stream pathname)
                                      (funcall thunk stream)))))
                      (close stream))
                    (cond
                      (after (return (funcall after pathname)))
                      (want-stream-p (return (values-list results)))
                      (want-pathname-p (return (and thunk (funcall thunk pathname))))
                      (t (return nil))))
               (when (and created-p (not (%temporary-file-keep-p keep)))
                 (ignore-errors (delete-file pathname)))))
      :finally
         (%with-host-operation (:call-with-temporary-file directory)
           (error "Unable to create a unique temporary file after ~D attempts in ~S"
                  attempts directory)))))

(defmacro with-temporary-file
    ((&key
      (stream (gensym "STREAM") streamp)
      (pathname (gensym "PATHNAME") pathnamep)
      directory prefix suffix type keep direction element-type external-format attempts)
     &body body)
  "Evaluate BODY with a temporary file stream and/or pathname.

When BODY contains :CLOSE-STREAM, forms before it run while STREAM is open
and forms after it run after the stream has been closed. The file is deleted
unless KEEP evaluates true after successful body evaluation."
  (unless (or streamp pathnamep)
    (error "WITH-TEMPORARY-FILE requires :STREAM and/or :PATHNAME"))
  (let* ((close-position (position :close-stream body))
         (before (if close-position (subseq body 0 close-position) body))
         (after (and close-position (subseq body (1+ close-position))))
         (before-function (gensym "BEFORE"))
         (after-function (gensym "AFTER"))
         (before-arguments (append (when streamp (list stream))
                                   (when pathnamep (list pathname)))))
    (when (and after (not pathnamep))
      (error "WITH-TEMPORARY-FILE requires :PATHNAME after :CLOSE-STREAM"))
    `(flet (,@(when before
                `((,before-function ,before-arguments
                    (declare (ignorable ,@before-arguments))
                    ,@before)))
            ,@(when after
                `((,after-function (,pathname)
                    (declare (ignorable ,pathname))
                    ,@after))))
       (call-with-temporary-file
        ,(when before `#',before-function)
        :want-stream-p ,streamp
        :want-pathname-p ,pathnamep
        ,@(when directory `(:directory ,directory))
        ,@(when prefix `(:prefix ,prefix))
        ,@(when suffix `(:suffix ,suffix))
        ,@(when type `(:type ,type))
        ,@(when keep `(:keep (lambda () ,keep)))
        ,@(when direction `(:direction ,direction))
        ,@(when element-type `(:element-type ,element-type))
        ,@(when external-format `(:external-format ,external-format))
        ,@(when attempts `(:attempts ,attempts))
        ,@(when after `(:after #',after-function))))))

#+sbcl
(defun call-with-atomic-output-file
    (target thunk &key (element-type 'character) (external-format :utf-8))
  "Call THUNK with an output stream and atomically replace TARGET on success.

THUNK is called with one argument, an output stream backed by a temporary file
in TARGET's directory. When THUNK returns normally, the stream is closed and
the temporary file replaces TARGET atomically. If THUNK or the replacement
fails, TARGET is left unchanged and the temporary file is removed."
  (unless (functionp thunk)
    (error "THUNK must be a function, got ~S." thunk))
  (let* ((target (ensure-absolute-pathname target))
         (directory (pathname-directory-pathname target))
         (temporary-pathname nil))
    (unwind-protect
         (multiple-value-prog1
             (call-with-temporary-file
              (lambda (stream pathname)
                (setf temporary-pathname pathname)
                (funcall thunk stream))
              :want-stream-p t
              :want-pathname-p t
              :direction :output
              :element-type element-type
              :external-format external-format
              :directory directory
              :keep t)
           (rename-file-overwriting-target temporary-pathname target))
      (when temporary-pathname
        (ignore-errors (delete-file temporary-pathname))))))

#-sbcl
(defun call-with-atomic-output-file
    (target thunk &key (element-type 'character) (external-format :utf-8))
  "Signal that atomic output files are unavailable on this implementation."
  (declare (ignore target thunk element-type external-format))
  (%unsupported :call-with-atomic-output-file))

(defmacro with-atomic-output-file
    ((stream target &key (element-type ''character) (external-format :utf-8))
     &body body)
  "Evaluate BODY with STREAM, atomically replacing TARGET if BODY succeeds."
  `(call-with-atomic-output-file
    ,target
    (lambda (,stream)
      ,@body)
    :element-type ,element-type
    :external-format ,external-format))

(defun read-file-string (pathspec)
  "Return the entire contents of the file PATHSPEC as a string."
  (%with-host-operation (:read-file-string pathspec)
    (with-open-file (stream pathspec :direction :input :external-format :utf-8)
      (let ((contents (make-string (file-length stream))))
        (let ((end (read-sequence contents stream)))
          (if (= end (length contents))
              contents
              (subseq contents 0 end)))))))

(defun write-file-string (string pathspec &key (external-format :utf-8))
  "Atomically write STRING to PATHSPEC and return its absolute pathname."
  (check-type string string)
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (call-with-atomic-output-file
     pathname
     (lambda (stream)
       (write-string string stream))
     :external-format external-format)
    pathname))

(defun read-file-octets (pathspec)
  "Return the entire contents of PATHSPEC as an octet vector."
  (%with-host-operation (:read-file-octets pathspec)
    (with-open-file (stream pathspec
                            :direction :input
                            :element-type '(unsigned-byte 8))
      (let ((contents (make-array (file-length stream)
                                  :element-type '(unsigned-byte 8))))
        (let ((end (read-sequence contents stream)))
          (if (= end (length contents))
              contents
              (subseq contents 0 end)))))))

(defun write-file-octets (octets pathspec)
  "Atomically write OCTETS to PATHSPEC and return its absolute pathname."
  (check-type octets (array (unsigned-byte 8) (*)))
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (call-with-atomic-output-file
     pathname
     (lambda (stream)
       (write-sequence octets stream))
     :element-type '(unsigned-byte 8))
    pathname))
