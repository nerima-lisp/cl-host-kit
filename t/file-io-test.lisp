;;;; t/file-io-test.lisp
(in-package #:cl-host-kit/test)

(describe
  "read-file-string"
  (it
    "returns the entire file contents as a string"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "a.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "hello, world" stream))
        (expect (read-file-string file) :to-equal "hello, world"))))
  (it
    "returns the exact UTF-8 string when character and byte lengths differ"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "utf-8.txt" scratch))
            (contents "日本語テキスト"))
        (write-file-string contents file)
        (expect (read-file-string file) :to-equal contents))))
  (it
    "reads text across its internal chunk boundary"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "large.txt" scratch))
            (contents (make-string 4097 :initial-element #\x)))
        (write-file-string contents file)
        (expect (read-file-string file) :to-equal contents))))
  (it
    "honors the requested external format"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "latin-1.txt" scratch))
            (contents (format nil "caf~C" (code-char #xE9))))
        (write-file-string contents file :external-format :latin-1)
        (expect (read-file-string file :external-format :latin-1) :to-equal contents))))
  (it
    "signals HOST-OPERATION-FAILED for a missing file"
    (signals
      host-operation-failed
      (read-file-string "/definitely/does/not/exist/cl-host-kit-xyz.txt"))))

(describe
  "read-file-lines"
  (it
    "returns lines without their terminators"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "lines.txt" scratch)))
        (write-file-string (format nil "first~%second~%third") file)
        (expect (read-file-lines file) :to-equal '("first" "second" "third")))))
  (it
    "returns NIL for an empty file"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "empty.txt" scratch)))
        (write-file-string "" file)
        (expect (read-file-lines file) :to-be nil))))
  (it
    "signals HOST-OPERATION-FAILED for a missing file"
    (signals
      host-operation-failed
      (read-file-lines "/definitely/does/not/exist/cl-host-kit-lines-xyz.txt"))))

(describe
  "call-with-file-string-chunks / with-file-string-chunks"
  (it
    "reads fresh exact character chunks in source order"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "chunks.txt" scratch))
            (contents
            (format
              nil
              "ab~C~C~Ccd"
              (code-char #x65E5)
              (code-char #x672C)
              (code-char #x8A9E)))
            (chunks (quote ())))
        (write-file-string contents file)
        (call-with-file-string-chunks
          (lambda (chunk)
            (push chunk chunks))
          file
          :buffer-size
          3)
        (setf chunks (nreverse chunks))
        (expect
          chunks
          :to-equal
          (list
            (format nil "ab~C" (code-char #x65E5))
            (format nil "~C~Cc" (code-char #x672C) (code-char #x8A9E))
            "d"))
        (expect (eq (first chunks) (second chunks)) :to-be nil))))
  (it
    "does not emit an empty final chunk at an exact buffer boundary"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "exact-chunks.txt" scratch))
            (chunks (quote ())))
        (write-file-string "abcdef" file)
        (call-with-file-string-chunks
          (lambda (chunk)
            (push chunk chunks))
          file
          :buffer-size
          3)
        (setf chunks (nreverse chunks))
        (expect chunks :to-equal (quote ("abc" "def")))
        (expect (eq (first chunks) (second chunks)) :to-be nil))))
  (it
    "stops when the callback returns :STOP"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "stop.txt" scratch))
            (chunks (quote ())))
        (write-file-string "abcdef" file)
        (call-with-file-string-chunks
          (lambda (chunk)
            (push chunk chunks)
            :stop)
          file
          :buffer-size
          2)
        (expect (nreverse chunks) :to-equal (quote ("ab"))))))
  (it
    "supports the lexical macro form and requested external format"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "latin-1.txt" scratch))
            (chunks (quote ()))
            (contents (format nil "caf~C" (code-char #xE9))))
        (write-file-string contents file :external-format :latin-1)
        (with-file-string-chunks
          (chunk file :external-format :latin-1 :buffer-size 2)
          (push chunk chunks))
        (expect
          (nreverse chunks)
          :to-equal
          (list "ca" (format nil "f~C" (code-char #xE9)))))))
  (it
    "validates arguments, bindings, and missing file failures"
    (with-scratch-directory
      (scratch)
      (let ((missing (merge-pathnames "missing.txt" scratch)))
        (signals type-error (call-with-file-string-chunks nil missing))
        (signals
          type-error
          (call-with-file-string-chunks
            (lambda (chunk)
              (declare (ignore chunk)))
            missing
            :buffer-size
            0))
        (signals
          error
          (macroexpand-1 (quote (with-file-string-chunks (42 "ignored") nil))))
        (signals
          error
          (macroexpand-1 (quote (with-file-string-chunks (nil "ignored") nil))))
        (signals
          host-operation-failed
          (call-with-file-string-chunks
            (lambda (chunk)
              (declare (ignore chunk)))
            missing))))))

(describe
  "call-with-file-lines / with-file-lines"
  (it
    "reads lines incrementally in source order"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "lines.txt" scratch))
            (lines '()))
        (write-file-string (format nil "first~%second~%third") file)
        (call-with-file-lines (lambda (line) (push line lines)) file)
        (expect (nreverse lines) :to-equal '("first" "second" "third")))))
  (it
    "stops without reading later lines when the callback returns :STOP"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "lines.txt" scratch))
            (lines '()))
        (write-file-string (format nil "first~%second~%third") file)
        (call-with-file-lines
         (lambda (line)
           (push line lines)
           (when (string= line "second") :stop))
         file)
        (expect (nreverse lines) :to-equal '("first" "second")))))
  (it
    "supports the lexical macro form and requested external format"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "latin-1.txt" scratch))
            (lines '())
            (contents (format nil "caf~C~%fin" (code-char #xE9))))
        (write-file-string contents file :external-format :latin-1)
        (with-file-lines (line file :external-format :latin-1)
          (push line lines))
        (expect (nreverse lines)
                :to-equal
                (list (format nil "caf~C" (code-char #xE9)) "fin")))))
  (it
    "validates the callback and reports a missing file"
    (with-scratch-directory
      (scratch)
      (let ((missing (merge-pathnames "missing.txt" scratch)))
        (signals type-error (call-with-file-lines nil missing))
        (signals error (macroexpand-1 '(with-file-lines (42 "ignored") nil)))
        (signals error (macroexpand-1 '(with-file-lines (nil "ignored") nil)))
        (signals host-operation-failed
                 (call-with-file-lines (lambda (line) (declare (ignore line))) missing))))))

(describe
  "call-with-file-octet-chunks / with-file-octet-chunks"
  (it
    "reads exact chunks in source order and permits retaining them"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "chunks.bin" scratch))
            (chunks '()))
        (write-file-octets
         (make-array 7 :element-type '(unsigned-byte 8)
                       :initial-contents '(0 1 2 3 4 5 255))
         file)
        (call-with-file-octet-chunks
         (lambda (chunk) (push chunk chunks))
         file
         :buffer-size 3)
        (setf chunks (nreverse chunks))
        (expect (mapcar (lambda (chunk) (coerce chunk 'list)) chunks)
                :to-equal
                '((0 1 2) (3 4 5) (255)))
        (expect (eq (first chunks) (second chunks)) :to-be nil))))
  (it
    "stops after the callback returns :STOP"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "chunks.bin" scratch))
            (chunks '()))
        (write-file-octets
         (make-array 7 :element-type '(unsigned-byte 8)
                       :initial-contents '(0 1 2 3 4 5 255))
         file)
        (call-with-file-octet-chunks
         (lambda (chunk)
           (push (coerce chunk 'list) chunks)
           :stop)
         file
         :buffer-size 3)
        (expect chunks :to-equal '((0 1 2))))))
  (it
    "supports the lexical macro form"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "chunks.bin" scratch))
            (total 0))
        (write-file-octets
         (make-array 4 :element-type '(unsigned-byte 8)
                       :initial-contents '(1 2 3 4))
         file)
        (with-file-octet-chunks (chunk file :buffer-size 2)
          (incf total (reduce #'+ chunk)))
        (expect total :to-equal 10))))
  (it
    "validates arguments and reports a missing file"
    (with-scratch-directory
      (scratch)
      (let ((missing (merge-pathnames "missing.bin" scratch)))
        (signals type-error (call-with-file-octet-chunks nil missing))
        (signals type-error
                 (call-with-file-octet-chunks (lambda (chunk) (declare (ignore chunk)))
                                              missing
                                              :buffer-size 0))
        (signals error (macroexpand-1 '(with-file-octet-chunks (42 "ignored") nil)))
        (signals error (macroexpand-1 '(with-file-octet-chunks (nil "ignored") nil)))
        (signals host-operation-failed
                 (call-with-file-octet-chunks (lambda (chunk) (declare (ignore chunk)))
                                              missing))))))

(describe
  "call-with-atomic-output-file / with-atomic-output-file"
  (it
    "replaces the target only after the writer completes"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch)))
        (write-file-string "old" target)
        (expect
          (multiple-value-list
            (call-with-atomic-output-file
              (lambda (stream)
                (write-string "new" stream)
                (values :first :second))
              target))
          :to-equal
          '(:first :second))
        (expect (read-file-string target) :to-equal "new"))))
  (it
    "preserves the previous target and removes the temporary file on failure"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch)))
        (write-file-string "old" target)
        (signals
          error
          (call-with-atomic-output-file
            (lambda (stream)
              (write-string "partial" stream)
              (error "expected test failure"))
            target))
        (expect (read-file-string target) :to-equal "old")
        (expect
          (mapcar #'file-namestring (directory-files scratch))
          :to-equal
          '("target.txt")))))
  (it
    "validates durability before replacing the target"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch)))
        (write-file-string "old" target)
        (signals
          type-error
          (call-with-atomic-output-file
            (lambda (stream)
              (declare (ignore stream)))
            target
            :synchronize :invalid))
        (signals
          type-error
          (call-with-atomic-output-file
            (lambda (stream)
              (declare (ignore stream)))
            target
            :if-exists :invalid))
        (expect (read-file-string target) :to-equal "old"))))
  (it
    "rejects an existing target before creating a temporary file"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch)))
        (write-file-string "old" target)
        (signals
          error
          (call-with-atomic-output-file
            (lambda (stream)
              (write-string "new" stream))
            target
            :if-exists :error))
        (expect (read-file-string target) :to-equal "old")
        (expect (mapcar #'file-namestring (directory-files scratch))
                :to-equal
                '("target.txt")))))
  (it "preserves an existing target's access permission bits"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "protected.txt" scratch)))
        (write-file-string "old" target)
        (sb-posix:chmod (namestring target) #o640)
        (write-file-string "new" target)
        (expect (logand #o777
                        (sb-posix:stat-mode (sb-posix:stat (namestring target))))
                :to-equal #o640)
        (expect (read-file-string target) :to-equal "new"))))
  (it "synchronizes the replacement and containing directory when requested"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "durable.txt" scratch)))
        (write-file-string "durable" target :synchronize t)
        ;; These calls exercise the same file and directory fsync operations
        ;; required by the durable atomic-write path.
        (expect (host-kit::%synchronize-pathname target) :to-equal 0)
        (expect (host-kit::%synchronize-pathname scratch) :to-equal 0)
        (expect (read-file-string target) :to-equal "durable"))))
  (it
    "binds an atomic output stream through the macro"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch)))
        (with-atomic-output-file
          (stream target :synchronize t)
          (write-string "macro" stream))
        (expect (read-file-string target) :to-equal "macro"))))
  (it-each ((42) (nil) (t))
      "rejects ~S as a stream binding during macroexpansion"
      (invalid-stream)
    (signals error (macroexpand-1 `(with-atomic-output-file (,invalid-stream "ignored") nil))))
  (it
    "forwards existing-target policy through the macro"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch)))
        (write-file-string "old" target)
        (signals
          error
          (with-atomic-output-file (stream target :if-exists :error)
            (write-string "new" stream)))
        (expect (read-file-string target) :to-equal "old")))))

(describe
  "whole-file writes and octets"
  (it
    "round-trips string data through an atomic write"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "text.txt" scratch)))
        (expect
          (write-file-string "hello, world" target :synchronize t)
          :to-equal
          (ensure-absolute-pathname target))
        (expect (read-file-string target) :to-equal "hello, world"))))
  (it
    "writes text lines atomically with a configurable terminator"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "lines.txt" scratch)))
        (expect
          (write-file-lines
            '("first" "second")
            target
            :line-terminator
            "\r\n"
            :synchronize
            t)
          :to-equal
          (ensure-absolute-pathname target))
        (expect (read-file-string target) :to-equal "first\r\nsecond\r\n"))))
  (it
    "validates all line input before replacing the target"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "lines.txt" scratch)))
        (write-file-string "old" target)
        (signals type-error (write-file-lines '("valid" 42) target))
        (expect (read-file-string target) :to-equal "old"))))
  (it
    "exposes existing-target rejection through every whole-file writer"
    (with-scratch-directory
      (scratch)
      (let ((string-target (merge-pathnames "string.txt" scratch))
            (lines-target (merge-pathnames "lines.txt" scratch))
            (octets-target (merge-pathnames "octets.bin" scratch)))
        (write-file-string "old" string-target)
        (write-file-string "old" lines-target)
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 7)
         octets-target)
        (signals error
                 (write-file-string "new" string-target :if-exists :error))
        (signals error
                 (write-file-lines '("new") lines-target :if-exists :error))
        (signals error
                 (write-file-octets
                  (make-array 1 :element-type '(unsigned-byte 8) :initial-element 9)
                  octets-target
                  :if-exists :error))
        (expect (read-file-string string-target) :to-equal "old")
        (expect (read-file-string lines-target) :to-equal "old")
        (expect (coerce (read-file-octets octets-target) 'list)
                :to-equal
                '(7)))))
  (it
    "round-trips unsigned octets through an atomic write"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "data.bin" scratch))
            (octets
            (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(0 1 127 255))))
        (write-file-octets octets target)
        (expect (coerce (read-file-octets target) 'list) :to-equal '(0 1 127 255)))))
  (it
    "reads empty and boundary-sized octet files"
    (with-scratch-directory
      (scratch)
      (dolist (size (quote (0 65536 65537 1048576 1048577)))
        (let* ((target (merge-pathnames (format nil "data-~D.bin" size) scratch))
               (octets (make-array size
                                   :element-type (quote (unsigned-byte 8))
                                   :initial-element 42)))
          (when (plusp size)
            (setf (aref octets (1- size)) 255))
          (write-file-octets octets target)
          (let ((read-octets (read-file-octets target)))
            (expect (length read-octets) :to-equal size)
            (expect (mismatch read-octets octets) :to-be nil))))))
  (it
    "copies large binary data to an absent target"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.bin" scratch))
            (target (merge-pathnames "target.bin" scratch))
            (octets (make-array 65537 :element-type '(unsigned-byte 8) :initial-element 42)))
        (setf (aref octets 65536) 255)
        (write-file-octets octets source)
        (expect
          (copy-file source target)
          :to-equal
          (ensure-absolute-pathname target))
        (let ((copied (read-file-octets target)))
          (expect (length copied) :to-equal (length octets))
          (expect (aref copied 0) :to-equal 42)
          (expect (aref copied 65535) :to-equal 42)
          (expect (aref copied 65536) :to-equal 255)))))
  (it
  "rejects a source replaced after metadata validation"
  (with-scratch-directory
    (scratch)
    (let ((source (merge-pathnames "source.bin" scratch))
          (replacement (merge-pathnames "replacement.bin" scratch))
          (target (merge-pathnames "target.bin" scratch)))
      (write-file-string "original" source)
      (write-file-string "replacement" replacement)
      (let ((metadata (file-metadata source)))
        (delete-file source)
        (rename-file replacement source)
        (signals error
          (host-kit::%copy-regular-file-atomically
           source target metadata nil nil ".host-kit-"))
        (expect (path-exists-p target) :to-be nil)))))
  (it
  "rejects a source whose recorded device no longer matches the opened file"
  (with-scratch-directory
    (scratch)
    (let* ((source (merge-pathnames "source.bin" scratch))
           (target (merge-pathnames "target.bin" scratch)))
      (write-file-string "payload" source)
      (let* ((real-metadata (file-metadata source))
             (mismatched-metadata
               (host-kit::%make-file-metadata
                :kind (file-metadata-kind real-metadata)
                :device (1+ (file-metadata-device real-metadata))
                :inode (file-metadata-inode real-metadata))))
        (signals error
          (host-kit::%copy-regular-file-atomically
           source target mismatched-metadata nil nil ".host-kit-"))
        (expect (path-exists-p target) :to-be nil)))))
  (it
  "copies metadata from the opened source inode"
  (with-scratch-directory
    (scratch)
    (let ((source (merge-pathnames "source.bin" scratch))
          (target (merge-pathnames "target.bin" scratch))
          (modification-time (- (get-universal-time) 3600)))
      (write-file-string "payload" source)
      (let ((stale-metadata (file-metadata source)))
        (set-file-mode source #o741)
        (set-file-times source :modification-time modification-time)
        (host-kit::%copy-regular-file-atomically
         source target stale-metadata nil nil ".host-kit-")
        (let ((copied-metadata (file-metadata target)))
          (expect (file-metadata-mode copied-metadata)
                  :to-equal
                  #o741)
          (expect (file-metadata-modification-time copied-metadata)
                  :to-equal
                  modification-time))))))
  (it
    "copies symbolic links exactly only when requested"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source" scratch))
            (source-link (merge-pathnames "source-link" scratch))
            (broken-link (merge-pathnames "broken-link" scratch))
            (followed-target (merge-pathnames "followed-target" scratch))
            (copied-link (merge-pathnames "copied-link" scratch))
            (replaced-link (merge-pathnames "replaced-link" scratch)))
        (write-file-string "payload" source)
        (create-symbolic-link "source" source-link)
        (copy-file source-link followed-target)
        (expect (symbolic-link-p followed-target) :to-be-falsy)
        (expect (read-file-string followed-target) :to-equal "payload")
        (create-symbolic-link "missing-relative-target" broken-link)
        (copy-file broken-link copied-link :follow-symlinks nil :synchronize t)
        (expect (symbolic-link-p copied-link) :to-be-truthy)
        (expect (read-symbolic-link copied-link) :to-equal "missing-relative-target")
        (write-file-string "old" replaced-link)
        (copy-file broken-link replaced-link
                   :follow-symlinks nil
                   :if-exists :supersede)
        (expect (symbolic-link-p replaced-link) :to-be-truthy)
        (expect (read-symbolic-link replaced-link) :to-equal "missing-relative-target"))))
  (it
    "preserves mode and timestamps when creating a new copy"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.bin" scratch))
            (target (merge-pathnames "target.bin" scratch))
            (access-time (- (get-universal-time) 7200))
            (modification-time (- (get-universal-time) 3600)))
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 1)
         source)
        (set-file-mode source #o751)
        (set-file-times source
                        :access-time access-time
                        :modification-time modification-time)
        (copy-file source target)
        (let ((metadata (file-metadata target)))
          (expect (file-metadata-mode metadata) :to-equal #o751)
          (expect (file-metadata-access-time metadata) :to-equal access-time)
          (expect (file-metadata-modification-time metadata)
                  :to-equal modification-time)))))
  (it
    "rejects an existing target without modifying it"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.bin" scratch))
            (target (merge-pathnames "target.bin" scratch)))
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 1)
         source)
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 7)
         target)
        (signals error (copy-file source target))
        (expect (coerce (read-file-octets target) 'list) :to-equal '(7)))))
  (it
    "replaces an existing target only when explicitly requested"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.bin" scratch))
            (target (merge-pathnames "target.bin" scratch)))
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 1)
         source)
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 7)
         target)
        (expect
         (copy-file source target :if-exists :supersede)
         :to-equal
         (ensure-absolute-pathname target))
        (expect (coerce (read-file-octets target) 'list) :to-equal '(1)))))
  (it
    "refuses to copy over the same file through direct, hard, and symbolic paths"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.bin" scratch))
            (hard-link (merge-pathnames "hard-link.bin" scratch))
            (symbolic-link (merge-pathnames "symbolic-link.bin" scratch)))
        (write-file-octets
         (make-array 1 :element-type '(unsigned-byte 8) :initial-element 1)
         source)
        (signals host-operation-failed
          (copy-file source source :if-exists :supersede))
        (create-hard-link source hard-link)
        (signals host-operation-failed
          (copy-file source hard-link :if-exists :supersede))
        (create-symbolic-link "source.bin" symbolic-link)
        (signals host-operation-failed
          (copy-file source symbolic-link :if-exists :supersede))
        (expect (coerce (read-file-octets source) 'list) :to-equal '(1))
        (expect (coerce (read-file-octets hard-link) 'list) :to-equal '(1))
        (expect (symbolic-link-p symbolic-link) :to-be-truthy))))
  (it
    "validates the replacement policy before opening either path"
    (signals type-error (copy-file "source.bin" "target.bin" :if-exists :invalid)))
  (it
    "validates symbolic-link traversal before opening either path"
    (signals type-error (copy-file "source.bin" "target.bin" :follow-symlinks :invalid)))
  (it
    "rejects missing and special sources before opening them"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "missing.bin" scratch))
            (target (merge-pathnames "target.bin" scratch)))
        (signals host-operation-failed (copy-file source target))
        (expect (path-exists-p target) :to-be nil))
      (let ((source (merge-pathnames "source-fifo" scratch))
            (target (merge-pathnames "fifo-target" scratch)))
        (sb-posix:mkfifo (namestring source) #o600)
        (signals host-operation-failed (copy-file source target))
        (expect (path-exists-p target) :to-be nil))))
  (it
    "copies a complete directory tree without following symbolic links"
    (with-scratch-directory
      (scratch)
      (let* ((source (merge-pathnames "source/" scratch))
             (nested (merge-pathnames "nested/" source))
             (empty (merge-pathnames "empty/" nested))
             (payload (merge-pathnames "payload.bin" nested))
             (link (merge-pathnames "missing-link" source))
             (target (merge-pathnames "target/" scratch))
             (octets
            (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(4 5 255))))
        (ensure-directory-tree empty)
        (write-file-octets octets payload)
        (set-file-mode source #o750)
        (set-file-mode nested #o750)
        (set-file-mode payload #o640)
        (create-symbolic-link "does-not-exist" link)
        (expect
          (copy-directory-tree source target :synchronize t)
          :to-equal
          (ensure-absolute-pathname target))
        (expect
          (coerce (read-file-octets (merge-pathnames "nested/payload.bin" target)) 'list)
          :to-equal
          '(4 5 255))
        (expect
          (directory-exists-p (merge-pathnames "nested/empty/" target))
          :to-be-truthy)
        (expect (symbolic-link-p (merge-pathnames "missing-link" target)) :to-be-truthy)
        (expect
          (read-symbolic-link (merge-pathnames "missing-link" target))
          :to-equal
          "does-not-exist")
          (expect (file-metadata-mode
                   (file-metadata (merge-pathnames "nested/payload.bin" target)))
                  :to-equal #o640))))
  (it
    "refuses an existing target without modifying it"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source/" scratch))
            (target (merge-pathnames "target/" scratch)))
        (ensure-directory-tree source)
        (write-file-string "source" (merge-pathnames "file.txt" source))
        (ensure-directory-tree target)
        (write-file-string "existing" (merge-pathnames "keep.txt" target))
        (signals host-operation-failed (copy-directory-tree source target))
        (expect
          (read-file-string (merge-pathnames "keep.txt" target))
          :to-equal
          "existing")))
    (it
      "reports a missing binary file as a host operation failure"
      (signals
        host-operation-failed
        (read-file-octets "/definitely/does/not/exist/cl-host-kit-xyz.bin")))))

(describe
  "copy-directory-tree validation"
  (it
    "rejects a non-directory source"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target/" scratch)))
        (write-file-string "source" source)
        (signals error (copy-directory-tree source target))
        (expect (directory-exists-p target) :to-be nil))))
  (it
    "rejects a target inside its source directory"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source/" scratch)))
        (ensure-directory-tree source)
        (signals error (copy-directory-tree source (merge-pathnames "nested/" source))))))
  (it
    "rejects a target that lexically escapes then re-enters its source"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source/" scratch)))
        (ensure-directory-tree source)
        (signals error
          (copy-directory-tree source
                               (merge-pathnames "nested/../copied/" source))))))
  (it
    "rejects a target parent symlinked into its source directory"
    (with-scratch-directory
      (scratch)
      (let* ((source (merge-pathnames "source/" scratch))
             (alias (merge-pathnames "source-alias" scratch))
             (target (merge-pathnames "copied/" alias)))
        (ensure-directory-tree source)
        (write-file-string "source" (merge-pathnames "file.txt" source))
        (create-symbolic-link (namestring source) alias)
        (signals host-operation-failed (copy-directory-tree source target))
        (expect (directory-exists-p target) :to-be nil)
        (expect (read-file-string (merge-pathnames "file.txt" source))
                :to-equal "source")))))

(describe
  "copy-path"
  (it
    "copies a regular file without replacing an existing target"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target.txt" scratch)))
        (write-file-string "source" source)
        (expect (copy-path source target)
                :to-equal
                (ensure-absolute-pathname target))
        (expect (read-file-string target) :to-equal "source")
        (write-file-string "existing" target)
        (signals host-operation-failed (copy-path source target))
        (expect (read-file-string target) :to-equal "existing"))))
  (it
    "copies a directory tree"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source/" scratch))
            (target (merge-pathnames "target/" scratch)))
        (ensure-directory-tree source)
        (write-file-string "payload" (merge-pathnames "file.txt" source))
        (expect (copy-path source target)
                :to-equal
                (ensure-absolute-pathname target))
        (expect (read-file-string (merge-pathnames "file.txt" target))
                :to-equal
                "payload"))))
  (it
    "preserves a broken symbolic link and rejects special entries"
    (with-scratch-directory
      (scratch)
      (let ((link (merge-pathnames "source-link" scratch))
            (copied-link (merge-pathnames "copied-link" scratch))
            (fifo (merge-pathnames "source-fifo" scratch))
            (target (merge-pathnames "fifo-target" scratch)))
        (create-symbolic-link "missing-relative-target" link)
        (copy-path link copied-link :synchronize t)
        (expect (symbolic-link-p copied-link) :to-be-truthy)
        (expect (read-symbolic-link copied-link)
                :to-equal
                "missing-relative-target")
        (sb-posix:mkfifo (namestring fifo) #o600)
        (signals host-operation-failed (copy-path fifo target))
        (expect (path-exists-p target) :to-be nil)))))

(describe
  "write-file-lines input validation"
  (it
    "rejects circular line lists before replacing the target"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "lines.txt" scratch))
            (lines (list "new"))
            (signalled-p nil))
        (setf (cdr lines) lines)
        (write-file-string "old" target)
        (handler-case
            (write-file-lines lines target)
          (type-error ()
            (setf signalled-p t)))
        (expect signalled-p :to-be-truthy)
        (expect (read-file-string target) :to-equal "old")))))

(describe
  "copy-directory-tree failure cleanup"
  (it
    "removes staging data when an unsupported source entry aborts the copy"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source/" scratch))
            (target (merge-pathnames "target/" scratch)))
        (ensure-directory-tree source)
        (sb-posix:mkfifo (namestring (merge-pathnames "unsupported" source)) #o600)
        (signals host-operation-failed (copy-directory-tree source target))
        (expect (directory-exists-p target) :to-be nil)
        (expect (subdirectories scratch)
                :to-equal
                (list source))))))


(cl-weave:describe-sequential "atomic file creation options"
  (it-each ((#o077) (#o000))
      "applies the exact requested mode after writing a private staging file under umask ~O"
      (mask)
    (cl-weave:expect-assertions 7)
    (let ((previous-mask (sb-posix:umask mask)))
      (unwind-protect
           (with-scratch-directory (scratch)
             (let ((target (merge-pathnames "new.txt" scratch))
                   (default-target (merge-pathnames "default.txt" scratch)))
               (call-with-atomic-output-file
                (lambda (stream)
                  (expect (string-prefix-p "#new.txt#." (file-namestring (pathname stream))) :to-be t)
                  (expect (file-metadata-mode (file-metadata (pathname stream))) :to-equal #o600)
                  (expect (path-exists-p target) :to-be nil)
                  (write-string "private" stream))
                target :mode #o664 :prefix "#new.txt#.")
               (expect (file-metadata-mode (file-metadata target)) :to-equal #o664)
               (write-file-string "replacement" target :mode #o600 :prefix "#new.txt#.")
               (expect (file-metadata-mode (file-metadata target)) :to-equal #o664)
               (write-file-string "default" default-target)
               (expect (file-metadata-mode (file-metadata default-target)) :to-equal #o600)
               (expect (sort (directory-files scratch) #'string< :key #'namestring)
                       :to-equal (list default-target target))))
        (sb-posix:umask previous-mask))))
  (it "forwards creation options through line and octet writers"
    (cl-weave:expect-assertions 2)
    (with-scratch-directory (scratch)
      (let ((lines (merge-pathnames "lines" scratch))
            (octets (merge-pathnames "octets" scratch)))
        (write-file-lines '("line") lines :mode #o640 :prefix "lines-")
        (write-file-octets (make-array 1 :element-type '(unsigned-byte 8) :initial-element 42)
                           octets :mode #o640 :prefix "octets-")
        (expect (file-metadata-mode (file-metadata lines)) :to-equal #o640)
        (expect (file-metadata-mode (file-metadata octets)) :to-equal #o640))))
  (it-each ((nil ".host-kit-") ("#copy#." "#copy#."))
      "uses regular copy staging prefix ~S while preserving source permissions"
      (prefix expected-prefix)
    (cl-weave:expect-assertions (if prefix 5 6))
    (with-scratch-directory (scratch)
      (let* ((source (merge-pathnames "source" scratch))
             (target (merge-pathnames "copy" scratch))
             (original (symbol-function 'host-kit::%copy-octet-stream))
             (staging-name nil))
        (write-file-string "contents" source)
        (set-file-mode source #o640)
        (with-function-redefinition
            ('host-kit::%copy-octet-stream
             (lambda (input output)
               (setf staging-name (file-namestring (pathname output)))
               (funcall original input output)))
          (if prefix
              (copy-file source target :prefix prefix)
              (copy-file source target)))
        (expect staging-name :to-be-truthy)
        (expect (string-prefix-p expected-prefix staging-name) :to-be t)
        (unless prefix
          (expect (string-prefix-p ".host-kit-copy-" staging-name) :to-be nil))
        (expect (read-file-string target) :to-equal "contents")
        (expect (file-metadata-mode (file-metadata target)) :to-equal #o640)
        (expect (subdirectories scratch) :to-equal nil))))
  (it-each ((nil ".host-kit-copy-") ("#link#." "#link#."))
      "uses symbolic-link copy staging prefix ~S"
      (prefix expected-prefix)
    (cl-weave:expect-assertions 4)
    (with-scratch-directory (scratch)
      (let* ((source (merge-pathnames "source-link" scratch))
             (target (merge-pathnames "copy-link" scratch))
             (original (symbol-function 'host-kit::%rename-path-overwriting-target))
             (staging-name nil))
        (sb-posix:symlink "missing-target" (namestring source))
        (with-function-redefinition
            ('host-kit::%rename-path-overwriting-target
             (lambda (staged destination)
               (setf staging-name (car (last (pathname-directory staged))))
               (funcall original staged destination)))
          (if prefix
              (copy-file source target :follow-symlinks nil :prefix prefix)
              (copy-file source target :follow-symlinks nil)))
        (expect staging-name :to-be-truthy)
        (expect (string-prefix-p expected-prefix staging-name) :to-be t)
        (expect (sb-posix:readlink (namestring target)) :to-equal "missing-target")
        (expect (subdirectories scratch) :to-equal nil))))
  (it "rejects invalid creation options without replacing a target"
    (cl-weave:expect-assertions 3)
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "unchanged" scratch)))
        (write-file-string "old" target)
        (signals type-error (write-file-string "new" target :mode -1))
        (signals error (write-file-string "new" target :prefix "../escape"))
        (expect (read-file-string target) :to-equal "old")))))


(describe "atomic publication permissions"
  (it "sets mode before rename and removes custom staging files on failure"
    (with-scratch-directory (scratch)
      (let* ((target (merge-pathnames "private" scratch))
             (original (symbol-function 'host-kit::%rename-path-overwriting-target))
             (observed nil))
        (unwind-protect
             (progn
               (setf (symbol-function 'host-kit::%rename-path-overwriting-target)
                     (lambda (source destination)
                       (expect (file-metadata-mode (file-metadata source)) :to-equal #o640)
                       (expect (path-exists-p destination) :to-be nil)
                       (setf observed t)
                       (funcall original source destination)))
               (write-file-string "private" target :mode #o640 :prefix "private-"))
          (setf (symbol-function 'host-kit::%rename-path-overwriting-target) original))
        (expect observed :to-be t)
        (signals host-operation-failed
          (call-with-atomic-output-file
           (lambda (stream) (write-string "unfinished" stream) (error "abort"))
           target :mode #o600 :prefix "private-"))
        (expect (read-file-string target) :to-equal "private")
        (expect (directory-files scratch) :to-equal (list target))))))


(describe "atomic synchronization with restrictive creation modes"
  (it-each ((#o000) (#o200))
      "publishes synchronized new files with mode ~O through their existing descriptor"
      (mode)
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "restricted" scratch)))
        (expect (write-file-string "contents" target :mode mode :synchronize t)
                :to-equal (ensure-absolute-pathname target))
        (expect (file-metadata-mode (file-metadata target)) :to-equal mode)
        (set-file-mode target #o600)
        (expect (read-file-string target) :to-equal "contents")))))

(describe "native literal file paths"
  (it "writes a new literal filename through atomic publication"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames (sb-ext:parse-native-namestring "new*?[\\.txt") scratch)))
        (write-file-string "fresh" target :mode #o640)
        (expect (read-file-string target) :to-equal "fresh")
        (expect (file-metadata-mode (file-metadata target)) :to-equal #o640))))
  (it "replaces a literal filename and preserves its existing permissions"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames (sb-ext:parse-native-namestring "existing*?[\\.txt") scratch)))
        (with-open-file (stream target :direction :output :if-exists :error)
          (write-string "old" stream))
        (sb-posix:chmod target #o640)
        (write-file-string "replacement" target :mode #o600)
        (expect (read-file-string target) :to-equal "replacement")
        (expect (file-metadata-mode (file-metadata target)) :to-equal #o640))))
  (it "copies between literal filenames without losing data or mode"
    (with-scratch-directory (scratch)
      (let ((source (merge-pathnames (sb-ext:parse-native-namestring "source*?[\\.txt") scratch))
            (target (merge-pathnames (sb-ext:parse-native-namestring "copy*?[\\.txt") scratch)))
        (with-open-file (stream source :direction :output :if-exists :error)
          (write-string "payload" stream))
        (sb-posix:chmod source #o640)
        (copy-file source target)
        (expect (read-file-string target) :to-equal "payload")
        (expect (file-metadata-mode (file-metadata target)) :to-equal #o640))))
  (it "keeps temporary directory names and prefix and suffix characters literal"
    (with-scratch-directory (scratch)
      (let ((parent (merge-pathnames (sb-ext:parse-native-namestring "parent*?[\\/") scratch)))
        (sb-posix:mkdir parent #o700)
        (call-with-temporary-file
         (lambda (stream path)
           (expect (pathname-directory path) :to-equal (pathname-directory parent))
           (let ((name (sb-ext:native-namestring
                        (make-pathname :directory nil :defaults path))))
             (expect (search "prefix*?[\\" name) :to-equal 0)
             (expect (search ".suffix*?[\\" name) :to-be-truthy))
           (write-string "temporary" stream)
           (finish-output stream)
           (expect (read-file-string path) :to-equal "temporary"))
         :directory parent :prefix "prefix*?[\\" :suffix ".suffix*?[\\")))))

(describe "native literal temporary directory paths"
  (it "keeps a generated directory prefix literal in the returned pathname"
    (with-scratch-directory (scratch)
      (call-with-temporary-directory
       (lambda (path)
         (expect (probe-file path) :to-be-truthy)
         (expect (file-metadata-kind (file-metadata path)) :to-equal :directory)
         (expect (search "directory*?[\\"
                         (car (last (pathname-directory path))))
                 :to-equal 0))
       :directory scratch :prefix "directory*?[\\"))))



