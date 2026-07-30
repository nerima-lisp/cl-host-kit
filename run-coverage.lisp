(progn
  (defun sbcl-contrib-fasl-pathname (module)
    (truename
      (merge-pathnames
        (format nil "../lib/sbcl/contrib/~(~A~).fasl" module)
        sb-ext:*runtime-pathname*)))
  (format t "~&coverage: initialize SB-COVER...~%")
  (finish-output)
  (load (sbcl-contrib-fasl-pathname "sb-cover"))
  (format t "~&coverage: SB-COVER initialized.~%")
  (finish-output))

(progn
  (declaim (optimize (sb-cover:store-coverage-data 0)))
  (require :asdf))

(progn
  (format t "~&coverage: initialize ASDF...~%")
  (finish-output)
  (asdf:initialize-source-registry
    (quote (:source-registry :ignore-inherited-configuration)))
  (format t "~&coverage: ASDF initialized.~%")
  (finish-output))

(defun script-directory ()
  (make-pathname
    :name
    nil
    :type
    nil
    :defaults
    (or
      *load-truename*
      *compile-file-truename*
      (error "Unable to determine the script location"))))

(progn
  (defun cl-weave-source-directory ()
    (or
      (sb-ext:posix-getenv "CL_HOST_KIT_CL_WEAVE_ROOT")
      (error "CL_HOST_KIT_CL_WEAVE_ROOT is required for coverage runs")))
  (defun configure-local-source-registry (root)
    (asdf:initialize-source-registry
      `(:source-registry
        (:tree ,root)
        (:tree ,(cl-weave-source-directory))
        :ignore-inherited-configuration))))

(defun coverage-report-directory ()
  (uiop:ensure-directory-pathname
    (or
      (sb-ext:posix-getenv "CL_HOST_KIT_COVERAGE_DIR")
      (merge-pathnames "coverage/" (truename ".")))))

(defun source-file-p (source-directory candidate)
  (let ((namestring (namestring candidate)))
    (and
      (<= (length source-directory) (length namestring))
      (string= source-directory namestring :end2 (length source-directory)))))

(defmacro with-coverage-phase ((name) &body body)
  `(let ((start-time (get-internal-real-time)))
    (format t "~&coverage: ~A...~%" ,name)
    (finish-output)
    (multiple-value-prog1
      (progn
        ,@body)
      (format
        t
        "~&coverage: ~A completed in ~,3F seconds~%"
        ,name
        (/ (- (get-internal-real-time) start-time) internal-time-units-per-second))
      (finish-output))))

(defun run-coverage ()
  (let* ((root (script-directory))
         (source-directory
           (namestring (truename (merge-pathnames "src/" root))))
         (report-directory (coverage-report-directory)))
    (with-coverage-phase ("configure source registry")
      (configure-local-source-registry root))
    ;; Reset before loading so the report includes executable top-level forms.
    (with-coverage-phase ("reset coverage")
      (sb-cover:reset-coverage))
    (with-coverage-phase ("load cl-host-kit")
      (asdf:load-system "cl-host-kit" :force t))
    (with-coverage-phase ("run cl-host-kit tests")
      (asdf:test-system "cl-host-kit/test"))
    (with-coverage-phase ("write HTML report")
      (sb-cover:report
        report-directory
        :if-matches
        (lambda (namestring)
          (source-file-p source-directory namestring))))
    (format
      t
      "~&Coverage report: ~A~%"
      (namestring (merge-pathnames "cover-index.html" report-directory)))))

(progn
  (declaim (optimize (sb-cover:store-coverage-data 3)))
  (format t "~&coverage: run initialized.~%")
  (finish-output))

(handler-case (progn
    (run-coverage)
    (sb-ext:exit :code 0))
  (error (condition)
    (format *error-output* "~&Coverage run failed: ~A~%" condition)
    (sb-ext:exit :code 1)))
