;;;; t/temporary-resources-test.lisp
(in-package #:cl-host-kit/test)

(describe
  "temporary-directory"
  (it
    "returns a directory-form pathname"
    (expect (directory-pathname-p (temporary-directory)) :to-be-truthy))
  (it
    "honors TMPDIR when set"
    (with-scratch-directory
      (scratch)
      (with-environment-variable
        ("TMPDIR" (namestring scratch))
        (expect (namestring (temporary-directory)) :to-equal (namestring scratch)))))
  (it
    "falls back to /tmp/ when TMPDIR is relative"
    (with-environment-variable
      ("TMPDIR" "relative-tmp/")
      (expect (namestring (temporary-directory)) :to-equal "/tmp/")))
  (it
    "falls back to /tmp when TMPDIR is unset"
    (with-environment-variable
      ("TMPDIR" nil)
      (expect (namestring (temporary-directory)) :to-equal "/tmp/")))
  (it
    "falls back to /tmp when TMPDIR is empty"
    (with-environment-variable
      ("TMPDIR" "")
      (expect (namestring (temporary-directory)) :to-equal "/tmp/"))))

(describe
  "call-with-temporary-directory / with-temporary-directory"
  (it
    "creates a private directory and removes it after a normal return"
    (let ((pathname nil))
      (expect
        (multiple-value-list
          (call-with-temporary-directory
            (lambda (directory)
              (setf pathname directory)
              (expect (directory-exists-p directory) :to-be-truthy)
              (values :first :second))))
        :to-equal
        '(:first :second))
      (expect (directory-exists-p pathname) :to-be nil)))
  (it
    "removes nested contents after the body signals"
    (let ((pathname nil))
      (signals
        error
        (call-with-temporary-directory
          (lambda (directory)
            (setf pathname directory)
            (ensure-directories-exist (merge-pathnames "nested/output.txt" directory))
            (with-open-file (stream
                (merge-pathnames "nested/output.txt" directory)
                :direction
                :output
                :if-does-not-exist
                :create)
              (write-string "data" stream))
            (error "expected test failure"))))
      (expect (directory-exists-p pathname) :to-be nil)))
  (it
    "preserves the directory when KEEP is true"
    (let ((pathname nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-directory #'identity :keep t))
          (expect (directory-exists-p pathname) :to-be-truthy))
        (when pathname
          (delete-directory-tree pathname :if-does-not-exist :ignore)))))
  (it
    "evaluates a KEEP predicate after a successful directory body"
    (let ((pathname nil)
          (keep-evaluated nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-directory
              #'identity
              :keep
              (lambda ()
                (setf keep-evaluated t)
                t)))
          (expect keep-evaluated :to-be-truthy)
          (expect (directory-exists-p pathname) :to-be-truthy))
        (when pathname
          (delete-directory-tree pathname :if-does-not-exist :ignore)))))
  (it
    "cleans the directory when its KEEP predicate signals"
    (let ((pathname nil))
      (signals
        error
        (call-with-temporary-directory
          (lambda (directory)
            (setf pathname directory))
          :keep
          (lambda ()
            (error "expected keep predicate failure"))))
      (expect (directory-exists-p pathname) :to-be nil)))
  (it
    "does not evaluate a directory KEEP predicate after a failing body"
    (let ((pathname nil)
          (keep-evaluated nil))
      (signals
        error
        (call-with-temporary-directory
          (lambda (directory)
            (setf pathname directory)
            (error "expected directory body failure"))
          :keep
          (lambda ()
            (setf keep-evaluated t)
            t)))
      (expect keep-evaluated :to-be nil)
      (expect (directory-exists-p pathname) :to-be nil)))
  (it
    "validates the directory callback and creation options"
    (signals type-error (call-with-temporary-directory nil))
    (signals
      type-error
      (call-with-temporary-directory (function identity) :prefix 1))
    (signals
      type-error
      (call-with-temporary-directory (function identity) :prefix "../escape-"))
    (signals
      type-error
      (call-with-temporary-directory
        (function identity)
        :prefix
        (format nil "bad~Cname" #\Null)))
    (signals
      type-error
      (call-with-temporary-directory (function identity) :attempts 0)))
  (it
    "binds a directory pathname through the macro"
    (let ((pathname nil))
      (with-temporary-directory
        (directory)
        (setf pathname directory)
        (expect (directory-pathname-p directory) :to-be-truthy))
      (expect (directory-exists-p pathname) :to-be nil)))
  (it-each ((42) (nil) (t))
      "rejects ~S as a directory binding during macroexpansion"
      (invalid-directory)
    (signals error (macroexpand-1 `(with-temporary-directory (,invalid-directory) nil))))
  (it
    "creates the directory under an explicit parent with its requested prefix"
    (with-scratch-directory
      (scratch)
      (let ((pathname nil))
        (call-with-temporary-directory
          (lambda (directory)
            (setf pathname directory)
            (expect
              (string-prefix-p (namestring scratch) (namestring directory))
              :to-be-truthy)
            (expect
              (string-prefix-p "build-" (car (last (pathname-directory directory))))
              :to-be-truthy))
          :directory
          scratch
          :prefix
          "build-")
        (expect (directory-exists-p pathname) :to-be nil))))
  (it
    "signals after exhausting directory creation attempts"
    (let ((calls 0))
      (with-function-redefinition
        ((quote host-kit::%create-temporary-directory)
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (incf calls)
            nil))
        (signals error (call-with-temporary-directory (function identity) :attempts 2))
        (expect calls :to-equal 2)))))

(describe
  "call-with-temporary-file / with-temporary-file"
  (it
    "closes and removes the file after a normal, multiple-value return"
    (let ((pathname nil))
      (expect
        (multiple-value-list
          (call-with-temporary-file
            (lambda (stream file)
              (setf pathname file)
              (write-string "temporary" stream)
              (values :first :second))))
        :to-equal
        '(:first :second))
      (expect (file-exists-p pathname) :to-be nil)))
  (it
    "removes the file after the body signals"
    (let ((pathname nil))
      (signals
        error
        (call-with-temporary-file
          (lambda (stream file)
            (setf pathname file)
            (write-string "temporary" stream)
            (error "expected test failure"))))
      (expect (file-exists-p pathname) :to-be nil)))
  (it
    "keeps the file only after a successful body"
    (let ((pathname nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-file
              (lambda (stream file)
                (write-string "kept" stream)
                file)
              :keep
              t))
          (expect (file-exists-p pathname) :to-be-truthy)
          (expect (read-file-string pathname) :to-equal "kept"))
        (when pathname
          (ignore-errors (delete-file pathname))))))
  (it
    "evaluates a KEEP predicate after a successful file body"
    (let ((pathname nil)
          (keep-evaluated nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-file
              (lambda (stream file)
                (declare (ignore stream))
                file)
              :keep
              (lambda ()
                (setf keep-evaluated t)
                t)))
          (expect keep-evaluated :to-be-truthy)
          (expect (file-exists-p pathname) :to-be-truthy))
        (when pathname
          (ignore-errors (delete-file pathname))))))
  (it
    "cleans the file when its KEEP predicate signals"
    (let ((pathname nil))
      (signals
        error
        (call-with-temporary-file
          (lambda (stream file)
            (declare (ignore stream))
            (setf pathname file))
          :keep
          (lambda ()
            (error "expected keep predicate failure"))))
      (expect (file-exists-p pathname) :to-be nil)))
  (it
    "does not evaluate a file KEEP predicate after a failing body"
    (let ((pathname nil)
          (keep-evaluated nil))
      (signals
        error
        (call-with-temporary-file
          (lambda (stream file)
            (declare (ignore stream))
            (setf pathname file)
            (error "expected file body failure"))
          :keep
          (lambda ()
            (setf keep-evaluated t)
            t)))
      (expect keep-evaluated :to-be nil)
      (expect (file-exists-p pathname) :to-be nil)))
  (it
    "supports binary temporary streams"
    (let ((pathname nil))
      (call-with-temporary-file
        (lambda (stream file)
          (setf pathname file)
          (write-byte #xAB stream))
        :element-type
        '(unsigned-byte 8))
      (expect (file-exists-p pathname) :to-be nil)))
  (it
    "supports empty suffixes and input-only streams"
    (let ((pathname nil))
      (call-with-temporary-file
        (lambda (stream file)
          (setf pathname file)
          (expect (read-line stream nil :empty) :to-equal :empty))
        :suffix
        ""
        :direction
        :input)
      (expect (file-exists-p pathname) :to-be nil)))
  (it
    "supports output-only UTF-8 streams beneath an explicit parent"
    (with-scratch-directory
      (scratch)
      (let ((pathname nil)
            (contents
            (format
              nil
              "temporary ~C~C~C"
              (code-char #x65E5)
              (code-char #x672C)
              (code-char #x8A9E))))
        (unwind-protect (progn
            (setf pathname (call-with-temporary-file
                (lambda (stream file)
                  (write-string contents stream)
                  file)
                :directory
                scratch
                :prefix
                "output-"
                :suffix
                ".txt"
                :direction
                :output
                :external-format
                :utf-8
                :keep
                t))
            (expect
              (string-prefix-p (namestring scratch) (namestring pathname))
              :to-be-truthy)
            (expect (read-file-string pathname) :to-equal contents))
          (when pathname
            (ignore-errors (delete-file pathname)))))))
  (it
    "synchronizes a successful output stream before retaining it"
    (let ((pathname nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-file
              (lambda (stream file)
                (write-string "synchronized" stream)
                file)
              :direction
              :output
              :keep
              t
              :synchronize
              t))
          (expect (read-file-string pathname) :to-equal "synchronized"))
        (when pathname
          (ignore-errors (delete-file pathname))))))
  (it
    "synchronizes a successful bidirectional stream before retaining it"
    (let ((pathname nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-file
              (lambda (stream file)
                (write-string "bidirectional" stream)
                file)
              :keep
              t
              :synchronize
              t))
          (expect (read-file-string pathname) :to-equal "bidirectional"))
        (when pathname
          (ignore-errors (delete-file pathname))))))
  (it
    "keeps a requested suffix while using a secure temporary name"
    (let ((pathname nil))
      (unwind-protect (progn
          (setf pathname (call-with-temporary-file
              (lambda (stream file)
                (write-string "suffix" stream)
                file)
              :suffix
              ".data"
              :keep
              t))
          (let ((namestring (namestring pathname)))
            (expect
              (string= ".data" (subseq namestring (- (length namestring) 5)))
              :to-be-truthy))
          (expect (read-file-string pathname) :to-equal "suffix"))
        (when pathname
          (ignore-errors (delete-file pathname))))))
  (it
    "validates the file callback and creation options"
    (signals type-error (call-with-temporary-file nil))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :suffix
        1))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :suffix
        "/escape"))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :suffix
        (format nil "bad~Cname" #\Null)))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :direction
        :probe))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :direction
        :input
        :synchronize
        t))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :synchronize
        :invalid))
    (signals
      type-error
      (call-with-temporary-file
        (lambda (stream file)
          (declare (ignore stream file)))
        :attempts
        0)))
  (it
    "binds stream and pathname through the macro"
    (let ((pathname nil))
      (with-temporary-file
        (stream file)
        (setf pathname file)
        (write-string "macro" stream))
      (expect (file-exists-p pathname) :to-be nil)))
  (it-each ((42 'file) (nil 'file) ('stream nil) ('stream t))
      "rejects ~S ~S as a stream/pathname binding pair during macroexpansion"
      (invalid-stream invalid-pathname)
    (signals error
             (macroexpand-1 `(with-temporary-file (,invalid-stream ,invalid-pathname) nil))))
  (it
    "signals after exhausting file creation attempts"
    (let ((calls 0))
      (with-function-redefinition
        ((quote host-kit::%open-temporary-file)
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (incf calls)
            (values nil nil)))
        (signals
          error
          (call-with-temporary-file
            (lambda (stream pathname)
              (declare (ignore stream pathname)))
            :attempts
            2))
        (expect calls :to-equal 2)))))

(describe
  "temporary resource failure boundaries"
  (it
    "signals when the temporary directory parent does not exist"
    (with-scratch-directory
      (scratch)
      (signals
        error
        (call-with-temporary-directory
          (function identity)
          :directory
          (merge-pathnames "missing-parent/" scratch)))))
  (it
    "signals when the temporary file parent does not exist"
    (with-scratch-directory
      (scratch)
      (signals
        error
        (call-with-temporary-file
          (lambda (stream pathname)
            (declare (ignore stream pathname)))
          :directory
          (merge-pathnames "missing-parent/" scratch)))))
  (it
    "rejects a regular file used as the temporary resource parent"
    (with-scratch-directory
      (scratch)
      (let ((parent (merge-pathnames "not-a-directory" scratch)))
        (write-file-string "preserved" parent)
        (signals
          error
          (call-with-temporary-directory
            (function identity)
            :directory
            parent))
        (signals
          error
          (call-with-temporary-file
            (lambda (stream pathname)
              (declare (ignore stream pathname)))
            :directory
            parent))
        (expect (read-file-string parent) :to-equal "preserved")))))
