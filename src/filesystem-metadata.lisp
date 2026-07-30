;;;; src/filesystem-metadata.lisp
;;;;
;;;; Filesystem metadata, links, permissions, and timestamps. Directory traversal
;;;; and destructive operations live in directory-operations.lisp.
(in-package #:host-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defconstant +unix-epoch-universal-time+ 2208988800
  "The Common Lisp universal time corresponding to the Unix epoch.")

(defstruct (file-metadata (:constructor %make-file-metadata)) "Filesystem metadata returned by FILE-METADATA.
KIND is one of :REGULAR-FILE, :DIRECTORY, :SYMBOLIC-LINK,
:CHARACTER-DEVICE, :BLOCK-DEVICE, :FIFO, :SOCKET, or :UNKNOWN. SIZE is in
  bytes. The three time values are Common Lisp universal times. DEVICE and INODE
  identify the filesystem object. MODE contains only the POSIX permission and
  special bits, not the file-kind bits."
  (kind :unknown :type keyword :read-only t)
  (size 0 :type (integer 0 *) :read-only t)
  (modification-time 0 :type integer :read-only t)
  (access-time 0 :type integer :read-only t)
  (change-time 0 :type integer :read-only t)
  (mode 0 :type (integer 0 #o7777) :read-only t)
  (device 0 :type (integer 0 *) :read-only t)
  (inode 0 :type (integer 0 *) :read-only t)
  (hard-link-count 0 :type (integer 0 *) :read-only t)
  (owner-id 0 :type (integer 0 *) :read-only t)
  (group-id 0 :type (integer 0 *) :read-only t))

(defun %unix-time->universal-time (unix-time)
  (+ +unix-epoch-universal-time+ unix-time))

(defun %universal-time->unix-time (universal-time)
  (- universal-time +unix-epoch-universal-time+))

(defun %file-kind (mode)
  (cond ((sb-posix:s-isreg mode) :regular-file)
        ((sb-posix:s-isdir mode) :directory)
        ((sb-posix:s-islnk mode) :symbolic-link)
        ((sb-posix:s-ischr mode) :character-device)
        ((sb-posix:s-isblk mode) :block-device)
        ((sb-posix:s-isfifo mode) :fifo)
        ((sb-posix:s-issock mode) :socket)
        (t :unknown)))

(defun %metadata-from-stat (stat)
  (let ((mode (sb-posix:stat-mode stat)))
    (%make-file-metadata
       :kind (%file-kind mode)
       :size (sb-posix:stat-size stat)
       :modification-time (%unix-time->universal-time (sb-posix:stat-mtime stat))
       :access-time (%unix-time->universal-time (sb-posix:stat-atime stat))
       :change-time (%unix-time->universal-time (sb-posix:stat-ctime stat))
       :mode (logand mode #o7777)
       :device (sb-posix:stat-dev stat)
       :inode (sb-posix:stat-ino stat)
       :hard-link-count (sb-posix:stat-nlink stat)
       :owner-id (sb-posix:stat-uid stat)
       :group-id (sb-posix:stat-gid stat))))

(defun file-metadata (pathspec &key (follow-symlinks t))
  "Return immutable FILE-METADATA for PATHSPEC.
When FOLLOW-SYMLINKS is true (the default), inspect the link target. When it
is NIL, inspect the directory entry itself, allowing a broken symbolic link to
be observed. Missing paths and invalid links signal HOST-OPERATION-FAILED."
  (check-type follow-symlinks boolean)
  (let ((pathname (ensure-pathname pathspec)))
    (%with-host-operation (:file-metadata pathname)
      (%metadata-from-stat
       (if follow-symlinks
           (sb-posix:stat (namestring pathname))
           (sb-posix:lstat (namestring pathname)))))))

(defun symbolic-link-p (pathspec)
  "Return true when PATHSPEC is a symbolic link, including a broken link.
Missing paths signal HOST-OPERATION-FAILED rather than being treated as links."
  (let ((pathname (ensure-pathname pathspec)))
    (%with-host-operation (:symbolic-link-p pathname)
      (sb-posix:s-islnk
       (sb-posix:stat-mode (sb-posix:lstat (namestring pathname)))))))

(defun read-symbolic-link (pathspec)
  "Return PATHSPEC's raw symbolic-link target as a string.
Relative targets remain relative to the link's containing directory. A missing
path or a path that is not a symbolic link signals HOST-OPERATION-FAILED."
  (let ((pathname (ensure-pathname pathspec)))
    (%with-host-operation (:read-symbolic-link pathname)
      (sb-posix:readlink (namestring pathname)))))

(defun create-symbolic-link (target link-pathspec)
  "Create LINK-PATHSPEC as a symbolic link to TARGET and return its absolute pathname.
TARGET may be a string or pathname. A string is stored without normalization,
so a relative target remains relative to the new link's containing directory.
Existing destination entries are never replaced."
  (check-type target (or string pathname))
  (let ((link (ensure-absolute-pathname link-pathspec))
        (target-namestring (if (pathnamep target) (namestring target) target)))
    (%with-host-operation (:create-symbolic-link link)
      (sb-posix:symlink target-namestring (namestring link)))
    link))

(defun create-hard-link (source link-pathspec)
  "Create LINK-PATHSPEC as a hard link to SOURCE and return its absolute pathname.
Existing destination entries are never replaced. SOURCE and LINK-PATHSPEC must
reside on the same filesystem, as required by POSIX."
  (let ((source (ensure-pathname source))
        (link (ensure-absolute-pathname link-pathspec)))
    (%with-host-operation (:create-hard-link (list source link))
      (sb-posix:link (namestring source) (namestring link)))
    link))

(defun set-file-mode (pathspec mode)
  "Set PATHSPEC's POSIX permission and special mode bits, returning its absolute pathname.
MODE is an integer from 0 through #o7777. Symbolic links are resolved, matching
POSIX CHMOD semantics."
  (check-type mode (integer 0 #o7777))
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (%with-host-operation (:set-file-mode pathname)
      (sb-posix:chmod (namestring pathname) mode))
    pathname))

(defun set-file-owner (pathspec &key (owner-id nil owner-id-p) (group-id nil group-id-p))
  "Set PATHSPEC owner and group IDs, returning its absolute pathname.
At least one of OWNER-ID and GROUP-ID must be supplied as a non-negative integer.
An omitted ID retains its observed value. Symbolic links are resolved, matching
POSIX CHOWN semantics."
  (unless (or owner-id-p group-id-p)
    (error "Specify at least one of OWNER-ID or GROUP-ID"))
  (when owner-id-p
    (check-type owner-id (integer 0 *)))
  (when group-id-p
    (check-type group-id (integer 0 *)))
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (%with-host-operation (:set-file-owner pathname)
      (let ((metadata (file-metadata pathname)))
        (sb-posix:chown (namestring pathname)
                        (if owner-id-p
                            owner-id
                            (file-metadata-owner-id metadata))
                        (if group-id-p
                            group-id
                            (file-metadata-group-id metadata)))))
    pathname))

(defun set-file-times (pathspec &key (access-time nil access-time-p)
                                (modification-time nil modification-time-p))
  "Set PATHSPEC access and modification times, returning its absolute pathname.
Times are non-negative Common Lisp universal times. An omitted time retains its
observed value; when both are omitted, both times are set to the current system
time. Symbolic links are resolved, matching POSIX UTIME semantics."
  (when access-time-p
    (check-type access-time (integer 0 *)))
  (when modification-time-p
    (check-type modification-time (integer 0 *)))
  (let ((pathname (ensure-absolute-pathname pathspec)))
    (%with-host-operation (:set-file-times pathname)
      (if (or access-time-p modification-time-p)
          (let ((metadata (file-metadata pathname)))
            (sb-posix:utime
             (namestring pathname)
             (%universal-time->unix-time
              (if access-time-p
                  access-time
                  (file-metadata-access-time metadata)))
             (%universal-time->unix-time
              (if modification-time-p
                  modification-time
                  (file-metadata-modification-time metadata)))))
          (sb-posix:utime (namestring pathname))))
    pathname))

(progn
  (defun path-exists-p (pathspec)
    "Return true when PATHSPEC names a directory entry without resolving links.
A missing entry or a path below a non-directory component returns NIL; a dangling
symbolic link returns true."
    (let ((pathname (ensure-absolute-pathname pathspec)))
      (%with-host-operation (:path-exists-p pathname)
        (handler-case
            (progn
              (sb-posix:lstat (namestring pathname))
              t)
          (sb-posix:syscall-error (condition)
            (if (member (sb-posix:syscall-errno condition)
                        (list sb-posix:enoent sb-posix:enotdir))
                nil
                (error condition))))))))

(defun file-exists-p (pathspec)
  "Return the truename of PATHSPEC if it exists and is not a directory, else
NIL."
  (let ((truename (probe-file pathspec)))
    (when (and truename (not (directory-pathname-p truename))) truename)))

(defun directory-exists-p (pathspec)
  "Return the truename of PATHSPEC if it exists and is a directory, else
NIL."
  (let ((truename (probe-file pathspec)))
    (when (and truename (directory-pathname-p truename)) truename)))

(defun same-file-p (left right)
  "Return true when LEFT and RIGHT resolve to the same filesystem object.

Symbolic links are followed. Missing paths and invalid links signal
HOST-OPERATION-FAILED."
  (let ((left-metadata (file-metadata left))
        (right-metadata (file-metadata right)))
    (and (= (file-metadata-device left-metadata)
            (file-metadata-device right-metadata))
         (= (file-metadata-inode left-metadata)
            (file-metadata-inode right-metadata)))))

(defun %file-accessible-p (pathspec access-mode)
  (let ((pathname (file-exists-p pathspec)))
    (and pathname
         (handler-case
             (zerop (sb-posix:access (namestring pathname) access-mode))
           (error () nil))
         pathname)))

(defun file-readable-p (pathspec)
  "Return the resolved truename of a readable non-directory PATHSPEC.
Return NIL when PATHSPEC is missing, denotes a directory, or is not readable
by the calling process. Symbolic links are resolved before checking access."
  (%file-accessible-p pathspec sb-posix:r-ok))

(defun file-writable-p (pathspec)
  "Return the resolved truename of a writable non-directory PATHSPEC.
Return NIL when PATHSPEC is missing, denotes a directory, or is not writable
by the calling process. Symbolic links are resolved before checking access."
  (%file-accessible-p pathspec sb-posix:w-ok))

(defun file-executable-p (pathspec)
  "Return the resolved truename of an executable non-directory PATHSPEC.
Return NIL when PATHSPEC is missing, denotes a directory, or is not executable
by the calling process. Symbolic links are resolved before checking access."
  (%file-accessible-p pathspec sb-posix:x-ok))

(progn
  (defun touch-file (pathspec &key (access-time nil access-time-p)
                                  (modification-time nil modification-time-p))
    "Create PATHSPEC when absent, update its timestamps, and return its absolute pathname.

Existing file contents are preserved. Times are non-negative Common Lisp universal
times; omitted times use the current system time. Symbolic links are resolved as
by POSIX UTIME. An existing directory, including one reached through a symbolic
link, signals HOST-OPERATION-FAILED."
    (when access-time-p
      (check-type access-time (integer 0 *)))
    (when modification-time-p
      (check-type modification-time (integer 0 *)))
    (let ((pathname (ensure-absolute-pathname pathspec)))
      (%with-host-operation (:touch-file pathname)
        (let ((existing (probe-file pathname)))
          (when (and existing (directory-pathname-p existing))
            (error "~S denotes a directory, not a file" pathname))
          (unless existing
            (with-open-file (stream pathname
                                    :direction :output
                                    :if-does-not-exist :create)
              (declare (ignore stream)))))
        (cond
          ((and access-time-p modification-time-p)
           (set-file-times pathname
                           :access-time access-time
                           :modification-time modification-time))
          (access-time-p
           (set-file-times pathname :access-time access-time))
          (modification-time-p
           (set-file-times pathname :modification-time modification-time))
          (t
           (set-file-times pathname)))
        pathname))))
