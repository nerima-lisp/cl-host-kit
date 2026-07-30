;;;; src/directory-operations.lisp
;;;;
;;;; Directory enumeration, traversal, creation, deletion, and renaming.
(in-package #:host-kit)

#+sbcl
(defun %directory-entry-names (directory)
  "Return DIRECTORY's entries, including dotfiles, in deterministic order."
  (%with-host-operation (:directory-entry-names directory)
    (let ((stream (sb-posix:opendir (namestring directory))))
      (unwind-protect
           (sort (loop for entry = (sb-posix:readdir stream)
                       while (and entry (not (sb-alien:null-alien entry)))
                       for name = (sb-posix:dirent-name entry)
                       unless (member name '("." "..") :test #'string=)
                         collect name)
                 #'string<)
        (sb-posix:closedir stream)))))

#+sbcl
(defun call-with-directory-entries (thunk pathspec &key (follow-symlinks nil))
  "Call THUNK for each direct entry in directory PATHSPEC.
THUNK receives an entry pathname and its immutable FILE-METADATA. Dotfiles are
included and entries are visited in lexical order. Symbolic-link metadata is
reported without following links unless FOLLOW-SYMLINKS is true. Returning
:STOP ends enumeration. The directory PATHSPEC itself is not yielded."
  (check-type thunk function)
  (check-type follow-symlinks boolean)
  (let ((directory (ensure-directory-pathname pathspec)))
    (%with-host-operation (:call-with-directory-entries directory)
      (unless (eq (file-metadata-kind (file-metadata directory)) :directory)
        (error "~S does not denote a directory" directory)))
    (dolist (name (%directory-entry-names directory))
      (let* ((entry (merge-pathnames name directory))
             (metadata (file-metadata entry :follow-symlinks follow-symlinks)))
        (when (eq (funcall thunk entry metadata) :stop)
          (return)))))
  (values))

#-sbcl
(defun call-with-directory-entries (thunk pathspec &key (follow-symlinks nil))
  (declare (ignore thunk pathspec follow-symlinks))
  (%unsupported 'call-with-directory-entries))

#+sbcl
   (defun directory-empty-p (pathspec)
     "Return true when PATHSPEC denotes an existing empty directory.
Dotfiles count as entries. A missing path or a non-directory signals
HOST-OPERATION-FAILED."
     (let ((directory (ensure-directory-pathname pathspec)))
       (%with-host-operation (:directory-empty-p directory)
         (unless (eq (file-metadata-kind (file-metadata directory)) :directory)
           (error "~S does not denote a directory" directory))
         (let ((stream (sb-posix:opendir (namestring directory))))
           (unwind-protect
                (loop for entry = (sb-posix:readdir stream)
                      while (and entry (not (sb-alien:null-alien entry)))
                      for name = (sb-posix:dirent-name entry)
                      unless (member name (quote ("." "..")) :test (function string=))
                        do (return nil)
                      finally (return t))
             (sb-posix:closedir stream))))))

#-sbcl
   (defun directory-empty-p (pathspec)
     (declare (ignore pathspec))
     (%unsupported (quote directory-empty-p)))

(defmacro with-directory-entries ((pathname metadata pathspec &key (follow-symlinks nil)) &body body)
  "Lexically bind PATHNAME and METADATA while enumerating PATHSPEC's entries."
  (unless (%macro-variable-name-p pathname)
    (error "PATHNAME must be a non-constant symbol: ~S" pathname))
  (unless (%macro-variable-name-p metadata)
    (error "METADATA must be a non-constant symbol: ~S" metadata))
  `(call-with-directory-entries
    (lambda (,pathname ,metadata)
      ,@body)
    ,pathspec
    :follow-symlinks
    ,follow-symlinks))

(defun directory-files (pathspec &key (follow-symlinks nil))
  "Return direct regular files in PATHSPEC in lexical order.
Dotfiles are included. Symbolic links are excluded by default; when
FOLLOW-SYMLINKS is true, links to regular files are included."
  (let ((files '()))
    (call-with-directory-entries
      (lambda (pathname metadata)
        (when (eq (file-metadata-kind metadata) :regular-file)
          (push pathname files)))
      pathspec
      :follow-symlinks follow-symlinks)
    (nreverse files)))

(defun subdirectories (pathspec &key (follow-symlinks nil))
  "Return direct subdirectories in PATHSPEC in lexical order.
Dot-directories are included. Symbolic links are excluded by default; when
FOLLOW-SYMLINKS is true, links to directories are included."
  (let ((directories '()))
    (call-with-directory-entries
      (lambda (pathname metadata)
        (when (eq (file-metadata-kind metadata) :directory)
          (push (ensure-directory-pathname pathname) directories)))
      pathspec
      :follow-symlinks follow-symlinks)
    (nreverse directories)))

#+sbcl
(progn
  (defun %directory-tree-identity (metadata)
    (cons (file-metadata-device metadata)
          (file-metadata-inode metadata)))

  (defun %directory-tree-mark-unvisited-p (directory visited)
    (let ((identity
            (%directory-tree-identity (file-metadata directory))))
      (unless (gethash identity visited)
        (setf (gethash identity visited) t)
        t)))

  (defun %directory-tree-may-yield-entries-p (depth max-depth)
    (or (null max-depth) (< depth max-depth)))

  (defun %walk-directory-tree-entry
      (thunk directory name depth follow-symlinks max-depth visited)
    (let* ((entry (merge-pathnames name directory))
           (metadata (file-metadata entry :follow-symlinks follow-symlinks))
           (directive (funcall thunk entry metadata (1+ depth))))
      (case directive
        (:stop :stop)
        (:skip-subtree nil)
        (otherwise
         (when (eq (file-metadata-kind metadata) :directory)
           (%walk-directory-tree
            thunk
            (ensure-directory-pathname entry)
            (1+ depth)
            follow-symlinks
            max-depth
            visited))))))

  (defun %walk-directory-tree
      (thunk directory depth follow-symlinks max-depth visited)
    (when (and (%directory-tree-mark-unvisited-p directory visited)
               (%directory-tree-may-yield-entries-p depth max-depth))
      (dolist (name (%directory-entry-names directory))
        (when (eq (%walk-directory-tree-entry
                   thunk directory name depth follow-symlinks max-depth visited)
                  :stop)
          (return :stop)))))

  (defun call-with-directory-tree
      (thunk pathspec &key (follow-symlinks nil) max-depth)
    "Call THUNK for every entry below directory PATHSPEC in depth-first order.
THUNK receives the entry pathname, its immutable FILE-METADATA, and its depth
relative to the root. Dotfiles are included and sibling entries are visited in
lexical order. Symbolic links are reported but not descended when
FOLLOW-SYMLINKS is NIL (the default). When it is true, directory links are
descended at most once per device/inode pair, so link cycles terminate.
Returning :SKIP-SUBTREE omits descent into that entry; returning :STOP ends the
walk. MAX-DEPTH is NIL or a non-negative integer; when supplied, only entries
at that depth or shallower are yielded. The root directory is not yielded and
has depth zero."
    (check-type thunk function)
    (check-type follow-symlinks boolean)
    (check-type max-depth (or null (integer 0 *)))
    (let ((root (ensure-directory-pathname pathspec))
          (visited (make-hash-table :test (function equal))))
      (%with-host-operation (:call-with-directory-tree root)
        (unless (eq (file-metadata-kind (file-metadata root)) :directory)
          (error "~S does not denote a directory" root)))
      (%walk-directory-tree thunk root 0 follow-symlinks max-depth visited))
    (values)))

#-sbcl
(defun call-with-directory-tree (thunk pathspec &key (follow-symlinks nil) max-depth)
  (declare (ignore thunk pathspec follow-symlinks max-depth))
  (%unsupported 'call-with-directory-tree))

(defmacro with-directory-tree
    ((pathname metadata depth pathspec &key (follow-symlinks nil) max-depth) &body body)
  "Lexically bind PATHNAME, METADATA, and DEPTH while walking PATHSPEC."
  (unless (%macro-variable-name-p pathname)
    (error "PATHNAME must be a non-constant symbol: ~S" pathname))
  (unless (%macro-variable-name-p metadata)
    (error "METADATA must be a non-constant symbol: ~S" metadata))
  (unless (%macro-variable-name-p depth)
    (error "DEPTH must be a non-constant symbol: ~S" depth))
  `(call-with-directory-tree
    (lambda (,pathname ,metadata ,depth)
      ,@body)
    ,pathspec
    :follow-symlinks
    ,follow-symlinks
    :max-depth
    ,max-depth))

(defun ensure-directory-tree (pathspec)
  "Create PATHSPEC and every missing parent directory, then return its truename.
PATHSPEC must denote a directory.  An existing regular file at the requested
location signals HOST-OPERATION-FAILED rather than being silently accepted."
  (let ((pathname (ensure-directory-pathname pathspec)))
    (%with-host-operation
      (:ensure-directory-tree pathname)
      (let ((existing (probe-file pathname)))
        (when (and existing (not (directory-pathname-p existing)))
          (error "~S is an existing regular file, not a directory" pathname)))
      (ensure-directories-exist (merge-pathnames ".directory-sentinel" pathname))
      (or
        (directory-exists-p pathname)
        (error "Unable to create directory ~S" pathname)))))

(defun delete-file-if-exists (pathspec)
  "Delete a regular file or symbolic link at PATHSPEC and return true.

A dangling symbolic link is removed as a link.  Return NIL when PATHSPEC is
missing, denotes a directory, or names another special filesystem entry."
  #+sbcl
  (let ((pathname (ensure-pathname pathspec)))
    (when (and (path-exists-p pathname)
               (member (file-metadata-kind
                        (file-metadata pathname :follow-symlinks nil))
                       '(:regular-file :symbolic-link)))
      (%with-host-operation (:delete-file-if-exists pathname)
        (delete-file pathname))
      t))
  #-sbcl
  (when (file-exists-p pathspec)
    (%with-host-operation (:delete-file-if-exists pathspec)
      (delete-file pathspec))
    t))

#+sbcl
(defun delete-empty-directory (pathspec)
  "Delete empty directory PATHSPEC. A missing or non-empty directory signals
HOST-OPERATION-FAILED."
  (let ((pathname (ensure-directory-pathname pathspec)))
    (%with-host-operation (:delete-empty-directory pathname)
      (sb-posix:rmdir (namestring pathname)))
    (values)))

#-sbcl
(defun delete-empty-directory (pathspec)
  (declare (ignore pathspec))
  (%unsupported 'delete-empty-directory))

#+sbcl
(progn
  (defun %final-entry-namestring (pathname)
    "Return the final entry spelling of PATHNAME without a resolving trailing slash."
    (let ((namestring (namestring pathname)))
      (if (and (> (length namestring) 1)
               (char= (char namestring (1- (length namestring))) #\/))
          (subseq namestring 0 (1- (length namestring)))
          namestring)))

  (defun %directory-deletion-symbolic-link-p (pathname)
    "Return true when the final directory entry of PATHNAME is a symbolic link."
    (sb-posix:s-islnk
     (sb-posix:stat-mode
      (sb-posix:lstat (%final-entry-namestring pathname)))))

  (defun delete-path (pathspec &key (recursive nil) (if-does-not-exist :error))
    "Delete PATHSPEC without following a final symbolic link.
When RECURSIVE is true, delete a real directory tree; links are always removed
as links. IF-DOES-NOT-EXIST is :ERROR (the default) or :IGNORE."
    (check-type recursive boolean)
    (check-type if-does-not-exist (member :error :ignore))
    (let* ((pathname (ensure-pathname pathspec))
           (entry-namestring (%final-entry-namestring pathname)))
      (%with-host-operation (:delete-path pathname)
        (handler-case
            (let ((mode (sb-posix:stat-mode
                         (sb-posix:lstat entry-namestring))))
              (if (sb-posix:s-isdir mode)
                  (if recursive
                      (progn
                        (delete-directory-tree pathname
                                               :if-does-not-exist :error)
                        t)
                      (progn
                        (sb-posix:rmdir entry-namestring)
                        t))
                  (progn
                    (sb-posix:unlink entry-namestring)
                    t)))
          (sb-posix:syscall-error (condition)
            (if (and (eq if-does-not-exist :ignore)
                     (member (sb-posix:syscall-errno condition)
                             (list sb-posix:enoent sb-posix:enotdir)))
                nil
                (error condition))))))))

#+sbcl
(defun delete-directory-tree (pathspec &key validate (if-does-not-exist :error))
  "Recursively delete directory PATHSPEC.
IF-DOES-NOT-EXIST is :ERROR (the default) or :IGNORE. When VALIDATE is true,
PATHSPEC must already be directory-form before anything is deleted. A symbolic
link used as the root is rejected, so deletion never traverses it. The
filesystem root, including an existing pathname that resolves to it, is also
rejected."
  (check-type validate boolean)
  (check-type if-does-not-exist (member :error :ignore))
  (let ((original (ensure-pathname pathspec)))
    (%with-host-operation (:delete-directory-tree original)
      (when (and validate (not (directory-pathname-p original)))
        (error "~S does not denote a directory" original))
      (let ((pathname (ensure-directory-pathname original)))
        (handler-case
            (progn
              (when (%filesystem-root-p pathname)
                (error "Refusing to recursively delete filesystem root ~S" original))
              (when (%directory-deletion-symbolic-link-p original)
                (error "Refusing to recursively delete symbolic link ~S" original))
              (sb-ext:delete-directory pathname :recursive t))
          (sb-posix:syscall-error (condition)
            (if (and (eq if-does-not-exist :ignore)
                     (= (sb-posix:syscall-errno condition) sb-posix:enoent))
                (values)
                (error condition)))
          (file-error (condition)
            ;; :IGNORE is only for a path that disappeared. Propagate
            ;; permission and I/O errors instead of reporting false success.
            (if (and (eq if-does-not-exist :ignore)
                     (not (probe-file pathname)))
                (values)
                (error condition)))))))
  (values))

#-sbcl
(progn
  (defun delete-path (pathspec &key recursive (if-does-not-exist :error))
    (declare (ignore pathspec recursive if-does-not-exist))
    (%unsupported (quote delete-path)))

  (defun delete-directory-tree (pathspec &key validate (if-does-not-exist :error))
    (declare (ignore pathspec validate if-does-not-exist))
    (%unsupported (quote delete-directory-tree))))

#+sbcl
(defun %rename-path-overwriting-target (source target)
  "Atomically rename SOURCE to TARGET, replacing TARGET when it exists."
  (sb-posix:rename (%final-entry-namestring source)
                   (%final-entry-namestring target)))

#+sbcl
(progn
  (defun %cross-device-error-p (condition)
    "Return true when CONDITION reports a cross-filesystem rename."
    (= (sb-posix:syscall-errno condition) sb-posix:exdev))

  (defun %move-staging-pathname (source staging-directory)
    "Return the staging entry pathname matching SOURCE entry kind."
    (let ((payload (merge-pathnames "payload" staging-directory)))
      (if (eq (file-metadata-kind
               (file-metadata source :follow-symlinks nil))
              :directory)
          (ensure-directory-pathname payload)
          payload)))

  (defun %move-path-across-filesystems (source target if-exists)
    "Copy SOURCE into TARGET filesystem, publish it, then remove SOURCE."
    (call-with-temporary-directory
     (lambda (staging-directory)
       (let ((staged-path (%move-staging-pathname source staging-directory)))
         (copy-path source staged-path)
         (when (and (eq if-exists :error) (path-exists-p target))
           (error "Target directory entry already exists: ~S" target))
         (%rename-path-overwriting-target staged-path target)
         (delete-path source :recursive t)))
     :directory (parent-directory-pathname target)
     :prefix ".host-kit-move-"))

  (defun %move-path-by-renaming-or-copying (source target if-exists)
    "Move SOURCE to TARGET, falling back to a staged copy after EXDEV."
    (handler-case
        (%rename-path-overwriting-target source target)
      (sb-posix:syscall-error (condition)
        (if (%cross-device-error-p condition)
            (%move-path-across-filesystems source target if-exists)
            (error condition)))))

  (defun move-path (source target &key (if-exists :error))
    "Move SOURCE to TARGET and return TARGET without following final symlinks.
SOURCE and TARGET name exact directory entries, rather than a source plus a
destination directory. IF-EXISTS is :ERROR (the default) or :SUPERSEDE.
The normal path uses POSIX rename and is atomic on one filesystem. A
cross-filesystem rename stages a copy under TARGET parent, publishes it with
an atomic target-local rename, then removes SOURCE. That fallback is not atomic
across both filesystems: a source-removal failure leaves both entries. :ERROR
rejects an existing target but cannot provide an atomic no-replace guarantee
against a concurrent creator."
    (check-type if-exists (member :error :supersede))
    (let ((source (ensure-absolute-pathname source))
          (target (ensure-absolute-pathname target)))
      (%with-host-operation (:move-path (list source target))
        (when (and (eq if-exists :error) (path-exists-p target))
          (error "Target directory entry already exists: ~S" target))
        (%move-path-by-renaming-or-copying source target if-exists))
      target)))

#-sbcl
(defun move-path (source target &key (if-exists :error))
  (declare (ignore source target if-exists))
  (%unsupported 'move-path))

(progn
  #+sbcl
  (defun create-directory (pathspec &key (mode #o777) (if-exists :error))
    "Create one directory at PATHSPEC without creating missing parents.
MODE is an integer from 0 through #o7777 and is filtered by the process umask.
IF-EXISTS is :ERROR (the default) or :IGNORE. With :IGNORE, an existing
directory is returned; every other existing entry still signals
HOST-OPERATION-FAILED. Return the created or existing directory's truename."
    (check-type mode (integer 0 #o7777))
    (check-type if-exists (member :error :ignore))
    (let ((pathname (ensure-directory-pathname pathspec)))
      (%with-host-operation
        (:create-directory pathname)
        (handler-case
            (sb-posix:mkdir (namestring pathname) mode)
          (sb-posix:syscall-error (condition)
            (let ((existing (directory-exists-p pathname)))
              (if (and (eq if-exists :ignore)
                       (= (sb-posix:syscall-errno condition) sb-posix:eexist)
                       existing)
                  (return-from create-directory existing)
                  (error condition))))))
      (or (directory-exists-p pathname)
          (error "Unable to create directory ~S" pathname))))
  #-sbcl
  (defun create-directory (pathspec &key (mode #o777) (if-exists :error))
    (declare (ignore pathspec mode if-exists))
    (%unsupported 'create-directory)))

#+sbcl
(defun %filesystem-root-p (pathname)
  "Return true when PATHNAME resolves to the filesystem root."
  (equal (pathname-directory
          (ensure-directory-pathname (truename pathname)))
         (quote (:absolute))))
