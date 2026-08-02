;;;; src/file-io.lisp
;;;;
;;;; Whole-file reads and atomic replacement writes.  Atomic writes depend on
;;;; TEMPORARY-RESOURCES and FILESYSTEM-QUERY being loaded first.
(in-package #:host-kit)

(defun %existing-file-mode (pathspec)
  "Return PATHSPEC's access permission bits when it is an existing regular file."
  (let ((pathname (file-exists-p pathspec)))
    (when pathname
      (logand #o777
              (sb-posix:stat-mode (sb-posix:stat (namestring pathname)))))))

(defun %apply-existing-file-mode (source target)
  "Copy SOURCE's existing access permission bits to TARGET before an atomic rename."
  (let ((mode (%existing-file-mode source)))
    (when mode
      (sb-posix:chmod (namestring target) mode))))

(defun %synchronize-pathname (pathname)
  "Synchronously persist PATHNAME's file data and metadata."
  (let ((descriptor nil))
    (unwind-protect
         (progn
           (setf descriptor (sb-posix:open (namestring pathname) sb-posix:o-rdonly))
           (sb-posix:fsync descriptor))
      (when descriptor
        (sb-posix:close descriptor)))))

(progn
  (defun %publish-atomic-output-file (target temporary-pathname directory synchronize)
    "Publish TEMPORARY-PATHNAME as TARGET after applying requested durability."
    ;; RENAME replaces the inode, so retain TARGET's access mode rather than
    ;; silently changing it to MKSTEMP's 0600 mode.
    (%apply-existing-file-mode target temporary-pathname)
    (when synchronize
      ;; CHMOD follows the stream fsync, so persist its metadata too.
      (%synchronize-pathname temporary-pathname))
    (%rename-path-overwriting-target temporary-pathname target)
    (when synchronize
      (%synchronize-pathname directory)))

  (defun call-with-atomic-output-file (thunk target &key (element-type 'character)
                                                         (external-format :utf-8)
                                                         (synchronize nil)
                                                         (if-exists :supersede))
    "Call THUNK with a stream whose completed contents atomically replace TARGET.
Failures before rename leave the old target untouched and remove the temporary
file.  When SYNCHRONIZE is true, persist replacement data and metadata before
rename, then persist the containing directory after rename.  A failure during
the final directory synchronization is reported after replacement.  IF-EXISTS is
:SUPERSEDE (the default) or :ERROR.  :ERROR rejects an existing target before
creating a temporary file, but cannot guarantee no replacement against a
concurrent creator."
    (check-type thunk function)
    (check-type synchronize boolean)
    (check-type if-exists (member :error :supersede))
    (let* ((target (ensure-absolute-pathname target))
           (directory (pathname-directory-pathname target))
           (temporary-pathname nil))
      (%with-host-operation (:call-with-atomic-output-file target)
        (when (and (eq if-exists :error) (path-exists-p target))
          (error "Target directory entry already exists: ~S" target))
        (unwind-protect
             (multiple-value-prog1
                 (call-with-temporary-file
                  (lambda (stream pathname)
                    (setf temporary-pathname pathname)
                    (funcall thunk stream))
                  :directory directory
                  :prefix ".host-kit-"
                  :suffix ".tmp"
                  :keep t
                  :direction :output
                  :element-type element-type
                  :external-format external-format
                  :synchronize synchronize)
               (%publish-atomic-output-file target temporary-pathname directory synchronize)
               (setf temporary-pathname nil))
          (when temporary-pathname
            (ignore-errors (delete-file temporary-pathname))))))))

(define-with-macro with-atomic-output-file (stream) call-with-atomic-output-file)

(defun %read-character-stream (stream)
  "Return every character remaining in STREAM without relying on FILE-LENGTH."
  (with-output-to-string (output)
    (let ((buffer (make-string 4096)))
      (loop for end = (read-sequence buffer stream)
            while (plusp end)
            do (write-string buffer output :end end)))))

(defun %read-octet-stream (stream)
  "Return every octet remaining in STREAM without relying on FILE-LENGTH."
  (let ((contents (make-array 65536
                              :element-type (quote (unsigned-byte 8))
                              :adjustable t))
        (size 0))
    (loop
      (when (= size (array-total-size contents))
        (let ((octet (read-byte stream nil nil)))
          (when (null octet)
            (return (adjust-array contents size)))
          (setf contents
                (adjust-array contents (* 2 (array-total-size contents))))
          (setf (aref contents size) octet)
          (incf size)))
      (let ((end (read-sequence contents stream
                                :start size
                                :end (array-total-size contents))))
        (when (= end size)
          (return (adjust-array contents size)))
        (setf size end)))))

(defun read-file-string (pathspec &key (external-format :utf-8))
  "Return the entire contents of the file PATHSPEC as a string."
  (%with-host-operation (:read-file-string pathspec)
    (with-open-file (stream pathspec :direction :input :external-format external-format)
      (%read-character-stream stream))))

(defun call-with-file-lines (thunk pathspec &key (external-format :utf-8))
  "Call THUNK with each line in PATHSPEC without its line terminator.
Lines are read incrementally, so file size does not determine heap use.
Returning :STOP ends enumeration.  The stream closes on every exit path."
  (check-type thunk function)
  (%with-host-operation (:call-with-file-lines pathspec)
    (with-open-file (stream pathspec :direction :input :external-format external-format)
      (loop for line = (read-line stream nil nil)
            while line
            when (eq (funcall thunk line) :stop)
              do (return))))
  (values))

(define-with-macro with-file-lines (line) call-with-file-lines)

(defun %call-with-fresh-stream-chunks (stream buffer thunk)
  "Read STREAM into BUFFER and pass fresh chunks to THUNK until exhaustion or :STOP."
  (loop for
        end = (read-sequence buffer stream)
        while (plusp end)
        for full-buffer-p = (= end (length buffer))
        for chunk = (if full-buffer-p buffer
      (subseq buffer 0 end))
        when (eq (funcall thunk chunk) :stop)
          do (return)
        when full-buffer-p
          do (setf buffer (make-array (length buffer) :element-type (array-element-type buffer)))))

(defun call-with-file-string-chunks (thunk pathname &key (buffer-size 65536) (external-format :default))
  "Call THUNK with each fresh string chunk read from PATHNAME.

THUNK may return :STOP to stop reading early.  BUFFER-SIZE is the maximum
number of characters in each chunk.  The function returns NIL."
  (check-type thunk function)
  (check-type buffer-size (integer 1))
  (%with-host-operation (:call-with-file-string-chunks pathname)
    (with-open-file (stream pathname
                            :direction :input
                            :element-type 'character
                            :external-format external-format)
      (let ((buffer (make-string buffer-size)))
        (%call-with-fresh-stream-chunks stream buffer thunk))))
  (values))

(define-with-macro with-file-string-chunks (chunk) call-with-file-string-chunks)

(defun read-file-lines (pathspec &key (external-format :utf-8))
  "Return the lines in PATHSPEC without their line terminators.
An empty final line is represented when the file ends with two consecutive
line terminators, matching repeated READ-LINE calls."
  (%with-host-operation (:read-file-lines pathspec)
    (with-open-file (stream pathspec :direction :input :external-format external-format)
      (loop for line = (read-line stream nil nil)
            while line
            collect line))))

(defun read-file-octets (pathspec)
  "Return the entire contents of PATHSPEC as an unsigned-byte 8 vector."
  (%with-host-operation (:read-file-octets pathspec)
    (with-open-file (stream pathspec :direction :input :element-type '(unsigned-byte 8))
      (%read-octet-stream stream))))

(defun call-with-file-octet-chunks (thunk pathname &key (buffer-size 65536))
  "Call THUNK with each fresh octet-vector chunk read from PATHNAME.

THUNK may return :STOP to stop reading early.  BUFFER-SIZE is the maximum
number of octets in each chunk.  The function returns NIL."
  (check-type thunk function)
  (check-type buffer-size (integer 1))
  (%with-host-operation (:call-with-file-octet-chunks pathname)
    (with-open-file (stream pathname
                            :direction :input
                            :element-type '(unsigned-byte 8))
      (let ((buffer (make-array buffer-size :element-type '(unsigned-byte 8))))
        (%call-with-fresh-stream-chunks stream buffer thunk))))
  (values))

(define-with-macro with-file-octet-chunks (chunk) call-with-file-octet-chunks)

(defun write-file-string (string pathspec &key (external-format :utf-8)
                                               (synchronize nil)
                                               (if-exists :supersede))
  "Atomically write STRING to PATHSPEC and return its absolute pathname.

IF-EXISTS is passed to CALL-WITH-ATOMIC-OUTPUT-FILE."
  (check-type string string)
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (call-with-atomic-output-file (lambda (stream) (write-string string stream))
                                    pathname
                                    :external-format external-format
                                    :synchronize synchronize
                                    :if-exists if-exists)
    pathname))

(defun write-file-lines (lines pathspec &key (external-format :utf-8)
                                                (line-terminator #\Newline)
                                                (synchronize nil)
                                                (if-exists :supersede))
  "Atomically write LINES to PATHSPEC and return its absolute pathname.
LINES must be a proper list of strings. LINE-TERMINATOR may be a character or
a string and is appended after every line, including the last one. IF-EXISTS is
passed to CALL-WITH-ATOMIC-OUTPUT-FILE."
  (check-type lines list)
  (unless (list-length lines)
    (error 'type-error :datum lines :expected-type 'list))
  (check-type line-terminator (or character string))
  (dolist (line lines)
    (check-type line string))
  (let ((pathname (ensure-absolute-pathname pathspec))
        (terminator (string line-terminator)))
    (call-with-atomic-output-file (lambda (stream)
                                    (dolist (line lines)
                                      (write-string line stream)
                                      (write-string terminator stream)))
                                  pathname
                                  :external-format external-format
                                  :synchronize synchronize
                                  :if-exists if-exists)
    pathname))

(defun write-file-octets (octets pathspec &key (synchronize nil)
                                           (if-exists :supersede))
  "Atomically write OCTETS to PATHSPEC and return its absolute pathname.

IF-EXISTS is passed to CALL-WITH-ATOMIC-OUTPUT-FILE."
  (check-type octets (array (unsigned-byte 8) (*)))
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (call-with-atomic-output-file (lambda (stream) (write-sequence octets stream))
                                    pathname
                                    :element-type '(unsigned-byte 8)
                                    :synchronize synchronize
                                    :if-exists if-exists)
    pathname))

(defun %copy-octet-stream (input output)
  (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8))))
    (loop for end = (read-sequence buffer input)
          while (plusp end)
          do (write-sequence buffer output :end end))))

(defun %copy-symbolic-link-atomically (source target synchronize)
  "Recreate SOURCE's link entry at TARGET through a same-parent staging path."
  (call-with-temporary-directory
   (lambda (staging-directory)
     (let ((staged-link (merge-pathnames "link" staging-directory)))
       (create-symbolic-link (read-symbolic-link source) staged-link)
       (%rename-path-overwriting-target staged-link target)
       (when synchronize
         (%synchronize-pathname (pathname-directory-pathname target)))))
   :directory (pathname-directory-pathname target)
   :prefix ".host-kit-copy-"))

(defun %copy-regular-file-atomically
    (source target source-metadata target-existed-p synchronize)
  (with-open-file (input source :direction :input
                               :element-type '(unsigned-byte 8))
    (let ((opened-metadata
            (%metadata-from-stat
             (sb-posix:fstat (sb-sys:fd-stream-fd input)))))
      (unless (and (eq (file-metadata-kind opened-metadata) :regular-file)
                   (= (file-metadata-device opened-metadata)
                      (file-metadata-device source-metadata))
                   (= (file-metadata-inode opened-metadata)
                      (file-metadata-inode source-metadata)))
        (error "SOURCE changed while preparing to copy it: ~S" source))
      (call-with-atomic-output-file
       (lambda (output)
         (%copy-octet-stream input output)
         (unless target-existed-p
           (%apply-copied-metadata-to-stream opened-metadata output)))
       target
       :element-type '(unsigned-byte 8)
       :synchronize synchronize))))

(progn
  (defun %validate-copy-file-source (source metadata follow-symlinks)
    (unless (or (eq (file-metadata-kind metadata) :regular-file)
                (and (not follow-symlinks)
                     (eq (file-metadata-kind metadata) :symbolic-link)))
      (error "COPY-FILE does not support source kind ~S: ~S"
             (file-metadata-kind metadata)
             source)))
  (defun %validate-copy-file-target (source target target-existed-p follow-symlinks)
    (when (and follow-symlinks target-existed-p (same-file-p source target))
      (error "SOURCE and TARGET denote the same file: ~S and ~S" source target)))
  (defun %copy-file-entry
    (source target metadata target-existed-p synchronize follow-symlinks)
  (if (and (not follow-symlinks)
           (eq (file-metadata-kind metadata) :symbolic-link))
      (%copy-symbolic-link-atomically source target synchronize)
      (%copy-regular-file-atomically
       source target metadata target-existed-p synchronize)))
  (defun %copy-file-with-metadata
      (source target metadata if-exists synchronize follow-symlinks)
    (let ((target-existed-p (path-exists-p target)))
      (when (and (eq if-exists :error) target-existed-p)
        (error "Target directory entry already exists: ~S" target))
      (%validate-copy-file-source source metadata follow-symlinks)
      (%validate-copy-file-target
       source target target-existed-p follow-symlinks)
      (%copy-file-entry
       source target metadata target-existed-p synchronize follow-symlinks)
      target))

  (defun copy-file (source target &key (if-exists :error) (synchronize nil)
                                        (follow-symlinks t))
    "Copy SOURCE to TARGET atomically and return TARGET.
IF-EXISTS is :ERROR (the default) or :SUPERSEDE. :ERROR rejects an existing
target, but cannot provide an atomic no-replace guarantee against a concurrent
creator. The copy is binary and streams bounded-size chunks, so source size does
not determine heap use. SOURCE must resolve to a regular file. When
FOLLOW-SYMLINKS is false, a symbolic SOURCE is recreated as a symbolic link
with its original link text. SOURCE and an existing TARGET must not denote the
same file when FOLLOW-SYMLINKS is true."
    (check-type if-exists (member :error :supersede))
    (check-type synchronize boolean)
    (check-type follow-symlinks boolean)
    (let ((source (ensure-absolute-pathname source))
          (target (ensure-absolute-pathname target)))
      (%with-host-operation (:copy-file (list source target))
        (%copy-file-with-metadata
         source target
         (file-metadata source :follow-symlinks follow-symlinks)
         if-exists synchronize follow-symlinks)))))

(progn
  (defun %descriptor-pathname (descriptor)
    "Return the stable descriptor pathname used for fd-relative metadata calls."
    (pathname (format nil "/dev/fd/~D" descriptor)))

  (defun %apply-copied-metadata-to-descriptor (metadata descriptor)
    "Apply portable copied metadata to the inode held open by DESCRIPTOR."
    (sb-posix:fchmod descriptor
                     (logand #o7777 (file-metadata-mode metadata)))
    (set-file-times (%descriptor-pathname descriptor)
                    :access-time (file-metadata-access-time metadata)
                    :modification-time
                    (file-metadata-modification-time metadata)))

  (defun %apply-copied-metadata-to-stream (metadata stream)
    "Apply copied metadata to the open STREAM inode before publication."
    (finish-output stream)
    (%apply-copied-metadata-to-descriptor
     metadata (sb-sys:fd-stream-fd stream)))

  (defun %apply-copied-metadata (metadata target)
    "Apply copied metadata to TARGET through a held descriptor."
    (let ((descriptor nil))
      (unwind-protect
           (progn
             (setf descriptor
                   (sb-posix:open (namestring target) sb-posix:o-rdonly))
             (%apply-copied-metadata-to-descriptor metadata descriptor))
        (when descriptor
          (sb-posix:close descriptor))))))

(progn
  (defun %copy-directory-tree-regular-file
    (source target metadata synchronize)
  (%validate-copy-file-source source metadata nil)
  (%copy-file-entry source target metadata nil synchronize nil))

  (defun %copy-directory-tree-symbolic-link (source target)
    ;; Preserve the link text so relative and dangling links retain their meaning.
    (create-symbolic-link (read-symbolic-link source) target))

  (defun %copy-directory-tree-directory (source target metadata synchronize)
    (let ((directory (ensure-directory-pathname target)))
      (ensure-directory-tree directory)
      (%copy-directory-tree-contents source directory synchronize)
      ;; Restrictive modes are safe only after descendants have been populated.
      (%apply-copied-metadata metadata directory)
      (when synchronize
        (%synchronize-pathname directory))))

  (defun %copy-directory-tree-entry (source target metadata synchronize)
    (case (file-metadata-kind metadata)
      (:regular-file
       (%copy-directory-tree-regular-file source target metadata synchronize))
      (:symbolic-link
       (%copy-directory-tree-symbolic-link source target))
      (:directory
       (%copy-directory-tree-directory source target metadata synchronize))
      (otherwise
       (error "COPY-DIRECTORY-TREE does not support ~S at ~S"
              (file-metadata-kind metadata) source)))))

(defun %copy-directory-tree-contents (source target synchronize)
  (call-with-directory-entries
   (lambda (entry metadata)
     (%copy-directory-tree-entry
      entry
      (merge-pathnames (file-namestring entry) target)
      metadata
      synchronize))
   source
   :follow-symlinks nil))

(progn
  (defun %validate-directory-tree-copy (source target source-metadata)
    "Validate the source and destination contract for a tree copy."
    (unless (eq (file-metadata-kind source-metadata) :directory)
      (error "~S does not denote a real directory" source))
    (when (or (pathname-within-p target source)
              (pathname-within-p target source :resolve-symlinks t))
      (error "Target ~S must not be SOURCE or a descendant of SOURCE ~S"
             target source))
    (when (path-exists-p target)
      (error "Target directory entry already exists: ~S" target)))

  (defun %stage-and-publish-directory-tree
      (source source-metadata target target-parent staging synchronize)
    "Copy SOURCE into STAGING and atomically publish it as TARGET."
    (%copy-directory-tree-contents source staging synchronize)
    (%apply-copied-metadata source-metadata staging)
    (when synchronize
      (%synchronize-pathname staging))
    ;; Recheck immediately before rename. POSIX cannot provide a portable
    ;; no-replace directory rename, so callers must still coordinate any
    ;; concurrent creator of TARGET.
    (when (path-exists-p target)
      (error "Target directory entry appeared while copying: ~S" target))
    (%rename-path-overwriting-target staging target)
    (when synchronize
      (%synchronize-pathname target-parent)))

  (defun copy-directory-tree (source target &key (synchronize nil))
    "Copy SOURCE's directory tree to an absent TARGET and return TARGET.
SOURCE must be a real directory, not a symbolic link. Regular files are copied
through atomic replacements; empty directories and symbolic links, including
broken links, are preserved. Modes plus access and modification times are
copied for regular files and directories. TARGET must remain absent until this
function publishes its same-parent staging directory, and may not be SOURCE,
a descendant of SOURCE, or resolve through a symbolic-link parent into SOURCE.
When SYNCHRONIZE is true, completed staged directories
and the target's parent are fsynced before and after publication respectively."
    (check-type synchronize boolean)
    (let* ((source
             (ensure-directory-pathname (ensure-absolute-pathname source)))
           (target
             (ensure-directory-pathname (ensure-absolute-pathname target)))
           (source-metadata
             (file-metadata source :follow-symlinks nil)))
      (%with-host-operation (:copy-directory-tree (list source target))
        (%copy-directory-tree-with-metadata
         source target source-metadata synchronize)))))

(defun copy-path (source target &key (synchronize nil))
  "Copy SOURCE's filesystem entry to an absent TARGET and return TARGET.
Regular files and symbolic links, including broken links, are copied without
resolving links. Real directories are copied through COPY-DIRECTORY-TREE.
Special filesystem entries such as FIFOs, sockets, and devices are rejected.
SYNCHRONIZE is passed to the selected copy operation."
  (check-type synchronize boolean)
  (let* ((source (ensure-absolute-pathname source))
         (target (ensure-absolute-pathname target))
         (metadata (file-metadata source :follow-symlinks nil)))
    (%with-host-operation (:copy-path (list source target))
      (case (file-metadata-kind metadata)
        ((:regular-file :symbolic-link)
         (%copy-file-with-metadata
          source target metadata :error synchronize nil))
        (:directory
         (%copy-directory-tree-with-metadata
          (ensure-directory-pathname source)
          (ensure-directory-pathname target)
          metadata synchronize))
        (otherwise
         (error "COPY-PATH does not support ~S at ~S"
                (file-metadata-kind metadata) source))))))
