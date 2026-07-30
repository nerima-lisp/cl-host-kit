;;;; t/filesystem-metadata-test.lisp
(in-package #:cl-host-kit/test)

#+sbcl
(describe "file-metadata / symbolic links"
  (it "distinguishes a link from its regular-file target"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "target.txt" scratch))
            (link (merge-pathnames "target-link" scratch)))
        (write-file-string "payload" target)
        (sb-posix:symlink (namestring target) (namestring link))
        (let ((target-metadata (file-metadata link))
              (link-metadata (file-metadata link :follow-symlinks nil))
              (directory-metadata (file-metadata scratch)))
          (expect (file-metadata-p target-metadata) :to-be-truthy)
          (expect (file-metadata-p link) :to-be-falsy)
          (expect (file-metadata-kind target-metadata) :to-equal :regular-file)
            (expect (file-metadata-size target-metadata) :to-equal 7)
            (expect (file-metadata-kind link-metadata) :to-equal :symbolic-link)
            (expect (file-metadata-size link-metadata)
                    :to-equal (length (namestring target)))
            (expect (file-metadata-mode target-metadata) :to-be-truthy)
            (expect (file-metadata-modification-time target-metadata) :to-be-truthy)
            (expect (integerp (file-metadata-access-time target-metadata)) :to-be-truthy)
            (expect (integerp (file-metadata-change-time target-metadata)) :to-be-truthy)
            (expect (integerp (file-metadata-device target-metadata)) :to-be-truthy)
            (expect (integerp (file-metadata-inode target-metadata)) :to-be-truthy)
            (expect (file-metadata-hard-link-count target-metadata) :to-equal 1)
            (expect (integerp (file-metadata-owner-id target-metadata)) :to-be-truthy)
            (expect (integerp (file-metadata-group-id target-metadata)) :to-be-truthy)
            (expect (file-metadata-kind directory-metadata) :to-equal :directory))
        (expect (symbolic-link-p link) :to-be-truthy)
        (expect (symbolic-link-p target) :to-be-falsy)
          (expect (read-symbolic-link link) :to-equal (namestring target)))))

  (it "reports the shared identity and link count of hard links"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "source.txt" scratch))
            (alias (merge-pathnames "alias.txt" scratch)))
        (write-file-string "payload" file)
        (sb-posix:link (namestring file) (namestring alias))
        (let ((file-metadata (file-metadata file))
              (alias-metadata (file-metadata alias)))
          (expect (file-metadata-device alias-metadata)
                  :to-equal (file-metadata-device file-metadata))
          (expect (file-metadata-inode alias-metadata)
                  :to-equal (file-metadata-inode file-metadata))
           (expect (file-metadata-hard-link-count file-metadata) :to-equal 2)
           (expect (file-metadata-hard-link-count alias-metadata) :to-equal 2)))))

  (it "creates hard links that share the source identity without replacing entries"
    (with-scratch-directory (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (link (merge-pathnames "alias.txt" scratch)))
        (write-file-string "payload" source)
        (expect (create-hard-link source link)
                :to-equal (ensure-absolute-pathname link))
        (expect (file-metadata-device (file-metadata link))
                :to-equal (file-metadata-device (file-metadata source)))
        (expect (file-metadata-inode (file-metadata link))
                :to-equal (file-metadata-inode (file-metadata source)))
        (expect (read-file-string link) :to-equal "payload")
        (signals host-operation-failed
          (create-hard-link source link))
        (expect (read-file-string link) :to-equal "payload"))))

  (it "observes a broken link without following it"
    (with-scratch-directory (scratch)
      (let ((link (merge-pathnames "broken-link" scratch))
            (missing (merge-pathnames "missing.txt" scratch)))
        (sb-posix:symlink (namestring missing) (namestring link))
        (expect (symbolic-link-p link) :to-be-truthy)
        (expect (file-metadata-kind (file-metadata link :follow-symlinks nil))
                :to-equal :symbolic-link)
        (signals host-operation-failed
          (file-metadata link)))))

  (it "creates relative symbolic links without normalizing their targets"
    (with-scratch-directory (scratch)
    (let ((target (merge-pathnames "target.txt" scratch))
          (link (merge-pathnames "target-link" scratch))
          (pathname-link (merge-pathnames "pathname-target-link" scratch)))
      (write-file-string "payload" target)
      (expect (create-symbolic-link "target.txt" link)
              :to-equal (ensure-absolute-pathname link))
      (expect (symbolic-link-p link) :to-be-truthy)
      (expect (read-symbolic-link link) :to-equal "target.txt")
      (expect (read-file-string link) :to-equal "payload")
      (expect (create-symbolic-link target pathname-link)
              :to-equal (ensure-absolute-pathname pathname-link))
      (expect (read-symbolic-link pathname-link) :to-equal (namestring target))
      (expect (read-file-string pathname-link) :to-equal "payload")
      (signals host-operation-failed
        (create-symbolic-link "target.txt" link))
        (signals type-error
          (create-symbolic-link 1 link)))))

  (it "classifies special files without opening them"
    (with-scratch-directory (scratch)
      (let ((fifo (merge-pathnames "events.fifo" scratch)))
        (sb-posix:mkfifo (namestring fifo) #o600)
        (expect (file-metadata-kind (file-metadata #P"/dev/null"))
                :to-equal :character-device)
        (expect (file-metadata-kind (file-metadata fifo))
                :to-equal :fifo))))

  (it "classifies every POSIX file-kind mode without host-specific device nodes"
    (expect (host-kit::%file-kind sb-posix:s-ifreg) :to-equal :regular-file)
    (expect (host-kit::%file-kind sb-posix:s-ifdir) :to-equal :directory)
    (expect (host-kit::%file-kind sb-posix:s-iflnk) :to-equal :symbolic-link)
    (expect (host-kit::%file-kind sb-posix:s-ifchr) :to-equal :character-device)
    (expect (host-kit::%file-kind sb-posix:s-ifblk) :to-equal :block-device)
    (expect (host-kit::%file-kind sb-posix:s-ififo) :to-equal :fifo)
    (expect (host-kit::%file-kind sb-posix:s-ifsock) :to-equal :socket)
    (expect (host-kit::%file-kind 0) :to-equal :unknown))

  (it "wraps metadata and link-read failures in host-operation-failed"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "regular.txt" scratch))
            (missing (merge-pathnames "missing.txt" scratch)))
        (write-file-string "payload" file)
        (signals host-operation-failed
          (file-metadata missing))
        (signals type-error
          (file-metadata file :follow-symlinks :invalid))
        (signals host-operation-failed
          (read-symbolic-link file))))))

#+sbcl
(describe "set-file-mode"
  (it "updates a file's permission bits and returns its absolute pathname"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "mode.txt" scratch)))
        (write-file-string "payload" file)
        (expect (set-file-mode file #o754)
                :to-equal (ensure-absolute-pathname file))
        (expect (file-metadata-mode (file-metadata file)) :to-equal #o754))))

  (it "follows symbolic links while preserving the link entry"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "target.txt" scratch))
            (link (merge-pathnames "target-link" scratch)))
        (write-file-string "payload" target)
        (create-symbolic-link "target.txt" link)
        (set-file-mode link #o700)
        (expect (file-metadata-mode (file-metadata target)) :to-equal #o700)
        (expect (symbolic-link-p link) :to-be-truthy))))

  (it "rejects invalid modes and wraps OS failures"
    (with-scratch-directory (scratch)
      (let ((missing (merge-pathnames "missing.txt" scratch)))
        (signals type-error (set-file-mode missing -1))
        (signals type-error (set-file-mode missing #o10000))
        (signals host-operation-failed (set-file-mode missing #o600))))))

#+sbcl
(describe "set-file-owner"
  (it "preserves omitted IDs, accepts both IDs, and follows symbolic links"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "owner.txt" scratch))
            (link (merge-pathnames "owner-link" scratch)))
        (write-file-string "payload" target)
        (create-symbolic-link "owner.txt" link)
        (let ((initial (file-metadata target)))
          (expect (set-file-owner link :owner-id (file-metadata-owner-id initial))
                  :to-equal (ensure-absolute-pathname link))
          (expect (set-file-owner target :group-id (file-metadata-group-id initial))
                  :to-equal (ensure-absolute-pathname target))
          (expect (set-file-owner
                   target
                   :owner-id (file-metadata-owner-id initial)
                   :group-id (file-metadata-group-id initial))
                  :to-equal (ensure-absolute-pathname target))
          (let ((result (file-metadata target)))
            (expect (file-metadata-owner-id result)
                    :to-equal (file-metadata-owner-id initial))
            (expect (file-metadata-group-id result)
                    :to-equal (file-metadata-group-id initial))))
        (expect (symbolic-link-p link) :to-be-truthy))))

  (it "validates IDs and wraps failures"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "owner.txt" scratch))
            (missing (merge-pathnames "missing.txt" scratch)))
        (write-file-string "payload" file)
        (signals error (set-file-owner file))
        (signals type-error (set-file-owner file :owner-id -1))
        (signals type-error (set-file-owner file :group-id :invalid))
        (signals host-operation-failed (set-file-owner missing :owner-id 0))))))

#+sbcl
(describe "set-file-times"
  (it "updates both timestamps using Common Lisp universal times"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "times.txt" scratch))
            (access-time 3900000001)
            (modification-time 3900000002))
        (write-file-string "payload" file)
        (expect (set-file-times file
                                :access-time access-time
                                :modification-time modification-time)
                :to-equal (ensure-absolute-pathname file))
        (let ((metadata (file-metadata file)))
          (expect (file-metadata-access-time metadata) :to-equal access-time)
          (expect (file-metadata-modification-time metadata)
                  :to-equal modification-time)))))

  (it "preserves an omitted timestamp and follows symbolic links"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "target.txt" scratch))
            (link (merge-pathnames "target-link" scratch))
            (access-time 3900000011)
            (initial-modification-time 3900000012)
            (modification-time 3900000013))
        (write-file-string "payload" target)
        (create-symbolic-link "target.txt" link)
        (set-file-times target
                        :access-time access-time
                        :modification-time initial-modification-time)
        (set-file-times link :modification-time modification-time)
        (let ((metadata (file-metadata target)))
          (expect (file-metadata-access-time metadata) :to-equal access-time)
          (expect (file-metadata-modification-time metadata)
                  :to-equal modification-time))
        (expect (symbolic-link-p link) :to-be-truthy))))

  (it "uses the current time by default and validates arguments"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "times.txt" scratch))
            (missing (merge-pathnames "missing.txt" scratch)))
        (write-file-string "payload" file)
        (set-file-times file
                        :access-time 3900000022
                        :modification-time 3900000023)
        (let ((before (get-universal-time)))
          (set-file-times file)
          (let ((metadata (file-metadata file))
                (after (get-universal-time)))
            (expect (<= before (file-metadata-access-time metadata) after)
                    :to-be-truthy)
            (expect (<= before (file-metadata-modification-time metadata) after)
                    :to-be-truthy)))
        (signals type-error (set-file-times file :access-time -1))
        (signals type-error (set-file-times file :modification-time :invalid))
        (signals host-operation-failed
          (set-file-times missing :access-time 3900000021))))))

(describe
  "file-exists-p / directory-exists-p"
  (it
    "file-exists-p returns the truename of an existing regular file"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "a.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "x" stream))
        (expect (file-exists-p file) :to-be-truthy)
        (expect (directory-pathname-p (file-exists-p file)) :to-be-falsy))))
  (it
    "file-exists-p is NIL for a directory"
    (with-scratch-directory (scratch) (expect (file-exists-p scratch) :to-be nil)))
  (it
    "file-exists-p is NIL for a missing path"
    (with-scratch-directory
      (scratch)
      (expect (file-exists-p (merge-pathnames "nope.txt" scratch)) :to-be nil)))
  (it
    "directory-exists-p returns the truename of an existing directory"
    (with-scratch-directory
      (scratch)
      (expect (directory-pathname-p (directory-exists-p scratch)) :to-be-truthy)))
  (it
    "directory-exists-p is NIL for a regular file"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "a.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "x" stream))
        (expect (directory-exists-p file) :to-be nil)))))

(describe
  "filesystem metadata boundary cases"
  (it
    "preserves modification time when only access time is specified"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "times.txt" scratch))
            (access-time 3900000031)
            (modification-time 3900000032))
        (write-file-string "payload" file)
        (set-file-times
          file
          :access-time
          access-time
          :modification-time
          modification-time)
        (set-file-times file :access-time (1+ access-time))
        (let ((metadata (file-metadata file)))
          (expect (file-metadata-access-time metadata) :to-equal (1+ access-time))
          (expect (file-metadata-modification-time metadata) :to-equal modification-time)))))
  (it
    "directory-exists-p is NIL for a missing path"
    (with-scratch-directory
      (scratch)
      (expect
        (directory-exists-p (merge-pathnames "missing-directory" scratch))
        :to-be
        nil))))

#+sbcl
(describe "file-executable-p"
  (it "returns the truename only for executable non-directory files"
    (with-scratch-directory (scratch)
      (let ((executable (merge-pathnames "executable" scratch))
            (ordinary-file (merge-pathnames "ordinary-file" scratch))
            (link (merge-pathnames "executable-link" scratch)))
        (write-file-string "#!/bin/sh~%exit 0~%" executable)
        (write-file-string "data" ordinary-file)
        (sb-posix:chmod (namestring executable) #o700)
        (sb-posix:chmod (namestring ordinary-file) #o600)
        (sb-posix:symlink (namestring executable) (namestring link))
        (expect (file-executable-p executable) :to-equal (truename executable))
        (expect (file-executable-p link) :to-equal (truename executable))
        (expect (file-executable-p ordinary-file) :to-be nil)
        (expect (file-executable-p scratch) :to-be nil)
        (expect (file-executable-p (merge-pathnames "missing" scratch)) :to-be nil)))))

#+sbcl
(describe "file-readable-p / file-writable-p"
  (it "return resolved truenames for regular files and symbolic links"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "accessible.txt" scratch))
            (link (merge-pathnames "accessible-link" scratch)))
        (write-file-string "payload" file)
        (sb-posix:chmod (namestring file) #o600)
        (sb-posix:symlink (namestring file) (namestring link))
        (expect (file-readable-p file) :to-equal (truename file))
        (expect (file-writable-p file) :to-equal (truename file))
        (expect (file-readable-p link) :to-equal (truename file))
        (expect (file-writable-p link) :to-equal (truename file)))))

  (it "return NIL for directories and missing paths"
    (with-scratch-directory (scratch)
      (let ((missing (merge-pathnames "missing" scratch)))
        (expect (file-readable-p scratch) :to-be nil)
        (expect (file-writable-p scratch) :to-be nil)
        (expect (file-readable-p missing) :to-be nil)
        (expect (file-writable-p missing) :to-be nil))))

  (it "return NIL when POSIX denies access"
    (with-scratch-directory (scratch)
      (let ((file (merge-pathnames "restricted.txt" scratch)))
        (write-file-string "payload" file)
        (sb-posix:chmod (namestring file) #o000)
        (unwind-protect
             (unless (zerop (sb-posix:geteuid))
               (expect (file-readable-p file) :to-be nil)
               (expect (file-writable-p file) :to-be nil)
               (expect (file-executable-p file) :to-be nil))
          (sb-posix:chmod (namestring file) #o600))))))

#+sbcl
(describe "same-file-p"
  (it "identifies hard links and resolved symbolic links"
    (with-scratch-directory (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (hard-link (merge-pathnames "hard-link.txt" scratch))
            (symbolic-link (merge-pathnames "symbolic-link" scratch))
            (other (merge-pathnames "other.txt" scratch)))
        (write-file-string "payload" source)
        (write-file-string "payload" other)
        (create-hard-link source hard-link)
        (create-symbolic-link "source.txt" symbolic-link)
        (expect (same-file-p source hard-link) :to-be-truthy)
        (expect (same-file-p source symbolic-link) :to-be-truthy)
        (expect (same-file-p source other) :to-be-falsy)
        (expect (same-file-p source #P"/dev/null") :to-be-falsy))))
  (it "signals the metadata error for missing paths"
    (with-scratch-directory (scratch)
      (signals host-operation-failed
        (same-file-p (merge-pathnames "missing.txt" scratch) scratch)))))

(when (member :sbcl *features*)
  (describe "touch-file"
    (it "creates an empty file and returns its absolute pathname"
      (with-scratch-directory (scratch)
        (let ((file (merge-pathnames "created.txt" scratch)))
          (expect (touch-file file) :to-equal (ensure-absolute-pathname file))
          (expect (file-exists-p file) :to-be-truthy)
          (expect (read-file-string file) :to-equal ""))))

    (it "preserves contents and applies explicitly requested times"
      (with-scratch-directory (scratch)
        (let ((file (merge-pathnames "existing.txt" scratch))
              (access-time 3900000041)
              (modification-time 3900000042))
          (write-file-string "payload" file)
          (touch-file file
                      :access-time access-time
                      :modification-time modification-time)
          (let ((metadata (file-metadata file)))
            (expect (file-metadata-access-time metadata) :to-equal access-time)
            (expect (file-metadata-modification-time metadata)
                     :to-equal modification-time))
          (expect (read-file-string file) :to-equal "payload"))))

    (it "preserves an omitted timestamp when updating an existing file"
      (with-scratch-directory (scratch)
        (let ((file (merge-pathnames "existing.txt" scratch))
              (access-time 3900000051)
              (modification-time 3900000052))
          (write-file-string "payload" file)
          (set-file-times file
                          :access-time access-time
                          :modification-time modification-time)
          (touch-file file :access-time (1+ access-time))
          (expect (file-metadata-access-time (file-metadata file))
                  :to-equal (1+ access-time))
          (expect (file-metadata-modification-time (file-metadata file))
                  :to-equal modification-time)
          (touch-file file :modification-time (1+ modification-time))
          (expect (file-metadata-access-time (file-metadata file))
                  :to-equal (1+ access-time))
          (expect (file-metadata-modification-time (file-metadata file))
                  :to-equal (1+ modification-time)))))

    (it "rejects directories without modifying their timestamps"
      (with-scratch-directory (scratch)
        (let ((access-time 3900000061)
              (modification-time 3900000062))
          (set-file-times scratch
                          :access-time access-time
                          :modification-time modification-time)
          (signals host-operation-failed
            (touch-file scratch))
          (let ((metadata (file-metadata scratch)))
            (expect (file-metadata-access-time metadata) :to-equal access-time)
            (expect (file-metadata-modification-time metadata)
                    :to-equal modification-time)))))

    (it "validates times before creating a missing file"
      (with-scratch-directory (scratch)
        (let ((file (merge-pathnames "missing.txt" scratch)))
          (signals type-error (touch-file file :access-time -1))
          (expect (file-exists-p file) :to-be nil))))))

(progn
  #+sbcl
  (describe "path-exists-p"
    (it "recognizes files, directories, and live symbolic links"
      (with-scratch-directory (scratch)
        (let ((file (merge-pathnames "entry.txt" scratch))
              (link (merge-pathnames "entry-link" scratch))
              (missing (merge-pathnames "missing.txt" scratch)))
          (write-file-string "payload" file)
          (create-symbolic-link "entry.txt" link)
          (expect (path-exists-p file) :to-be-truthy)
          (expect (path-exists-p scratch) :to-be-truthy)
          (expect (path-exists-p link) :to-be-truthy)
          (expect (path-exists-p missing) :to-be nil))))
    (it "recognizes dangling links without resolving them"
      (with-scratch-directory (scratch)
        (let ((link (merge-pathnames "broken-link" scratch)))
          (create-symbolic-link "missing.txt" link)
          (expect (path-exists-p link) :to-be-truthy))))
    (it "returns NIL below a regular-file component"
      (with-scratch-directory (scratch)
        (let ((file (merge-pathnames "not-a-directory" scratch)))
          (write-file-string "payload" file)
          (expect (path-exists-p
                   (merge-pathnames "not-a-directory/child" scratch))
                  :to-be nil))))))
