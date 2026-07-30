;;;; microbench.lisp --- Repeatable microbenchmarks for cl-host-kit
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
      (error "Cannot determine the benchmark script location."))))

(defun checkout-root ()
  (truename (merge-pathnames "../" (script-directory))))

;; UIOP is loaded only for an external benchmark baseline, not at runtime.
(require :asdf)

(defparameter +warmup-samples+ 3)

(defparameter +measured-samples+ 7)

(defparameter *benchmark-sink* 0)

(unless (find-package (quote #:host-kit))
  (require :asdf)
  (funcall (symbol-function (find-symbol "LOAD-SYSTEM" :asdf)) "cl-host-kit"))

(defun median (values)
  (let* ((sorted (sort (copy-seq values) #'<))
         (middle (floor (length sorted) 2)))
    (elt sorted middle)))

(defun consume-result (value)
  (setf *benchmark-sink* (logxor *benchmark-sink* (sxhash value))))

(defun measure-sample (operations function)
  (let ((start-time (get-internal-real-time))
        (start-bytes (sb-ext:get-bytes-consed)))
    (dotimes (index operations)
      (declare (ignore index))
      (consume-result (funcall function)))
    (values
      (/
        (- (get-internal-real-time) start-time)
        internal-time-units-per-second
        operations)
      (/ (- (sb-ext:get-bytes-consed) start-bytes) operations))))

(defparameter +calibration-target-seconds+ 0.02d0)

(defparameter +maximum-calibration-operations+ 250)

(defun calibrated-operations (minimum-operations maximum-operations function)
  (loop with operations = minimum-operations
        for seconds-per-operation = (nth-value 0 (measure-sample operations function))
        for total-seconds = (* seconds-per-operation operations)
        while (and
      (< total-seconds +calibration-target-seconds+)
      (< operations maximum-operations))
        do (setf operations (min maximum-operations (* operations 2)))
        finally (return operations)))

(defun benchmark-case (name
    operations
    function
    &key
    (maximum-operations +maximum-calibration-operations+))
  (format t "~&Running ~A...~%" name)
  (finish-output)
  (let ((operations (calibrated-operations operations maximum-operations function)))
    ;; Keep allocations from the warmup phase out of measured samples.
    (sb-ext:gc :full t)
    (dotimes (sample +warmup-samples+)
      (declare (ignore sample))
      (measure-sample operations function))
    (sb-ext:gc :full t)
    (let ((elapsed (make-array +measured-samples+))
          (bytes (make-array +measured-samples+)))
      (dotimes (sample +measured-samples+)
        (multiple-value-bind (sample-elapsed sample-bytes) (measure-sample operations function)
          (setf (aref elapsed sample) sample-elapsed
                (aref bytes sample) sample-bytes)))
      (let ((microseconds (* 1000000.0 (median elapsed)))
            (bytes-per-operation (median bytes)))
        (format
          t
          "~&~A (~D ops): ~,2F us/op, ~,1F B/op~%"
          name
          operations
          microseconds
          bytes-per-operation)
        (finish-output)
        (values microseconds bytes-per-operation)))))

(defun benchmark-comparison (name
    operations
    host-function
    reference-function
    &key
    (maximum-operations +maximum-calibration-operations+)
    (result-test (function equalp)))
  (unless (funcall result-test (funcall host-function) (funcall reference-function))
    (error "Benchmark comparison ~A has incompatible results." name))
  (multiple-value-bind (host-microseconds host-bytes) (benchmark-case
      (format nil "~A host-kit" name)
      operations
      host-function
      :maximum-operations
      maximum-operations)
    (multiple-value-bind (reference-microseconds reference-bytes) (benchmark-case
        (format nil "~A UIOP" name)
        operations
        reference-function
        :maximum-operations
        maximum-operations)
      (format
        t
        "~&~A relative to UIOP: ~,2Fx time, ~,2Fx allocation (< 1 is lower)~%"
        name
        (/ host-microseconds reference-microseconds)
        (if (zerop reference-bytes) 0.0
          (/ host-bytes reference-bytes)))
      (finish-output))))

(defun repeated-string (character count)
  (make-string count :initial-element character))

(defun split-input ()
  (with-output-to-string (stream)
    (dotimes (field 100)
      (declare (ignore field))
      (write-string "token," stream))))

(defun separator-string (width)
  (let ((separator (repeated-string #\x width)))
    (setf (char separator 0) #\,)
    separator))

(defun relative-path (depth)
  (with-output-to-string (stream)
    (dotimes (component depth)
      (declare (ignore component))
      (write-string "component/" stream))
    (write-string "file.txt" stream)))

(defun temporary-directory ()
  (let ((directory
        (merge-pathnames
          (format
            nil
            "cl-host-kit-microbench-~D-~D/"
            (get-universal-time)
            (random most-positive-fixnum))
          (host-kit:temporary-directory))))
    (ensure-directories-exist directory)
    directory))

(defun write-ascii-file (pathname bytes)
  (with-open-file (stream
      pathname
      :direction
      :output
      :if-exists
      :supersede
      :external-format
      :utf-8)
    (write-string (repeated-string #\A bytes) stream)))

(defun write-utf8-file (pathname bytes)
  (with-open-file (stream
      pathname
      :direction
      :output
      :if-exists
      :supersede
      :external-format
      :utf-8)
    (dotimes (character (/ bytes 2))
      (declare (ignore character))
      (write-char (code-char #x00E9) stream))))

(defun benchmark-splits ()
  (let ((input (split-input))
        (maximum-operations 25))
    (benchmark-case
      "split char"
      1
      (lambda ()
        (host-kit:split-string input :separator #\,))
      :maximum-operations
      maximum-operations)
    (dolist (width (quote (1 16 64)))
      (let ((string-separator (separator-string width)))
        (benchmark-case
          (format nil "split string/~D" width)
          1
          (lambda ()
            (host-kit:split-string input :separator string-separator))
          :maximum-operations
          maximum-operations)
        (let ((list-separator (coerce string-separator (quote list))))
          (benchmark-case
            (format nil "split list/~D" width)
            1
            (lambda ()
              (host-kit:split-string input :separator list-separator))
            :maximum-operations
            maximum-operations))))
    (benchmark-comparison
      "split char"
      1
      (lambda ()
        (host-kit:split-string input :separator #\,))
      (lambda ()
        (uiop:split-string input :separator ","))
      :maximum-operations
      maximum-operations)))

(defun benchmark-pathnames ()
  (dolist (depth (quote (1 10 50)))
    (let ((path (relative-path depth)))
      (benchmark-case
        (format nil "ensure-directory/~D" depth)
        100
        (lambda ()
          (host-kit:ensure-directory-pathname path)))
      (benchmark-case
        (format nil "ensure-absolute/~D" depth)
        100
        (lambda ()
          (host-kit:ensure-absolute-pathname path)))))
  (let ((path (relative-path 10)))
    (benchmark-comparison
      "ensure-directory/10"
      100
      (lambda ()
        (host-kit:ensure-directory-pathname path))
      (lambda ()
        (uiop:ensure-directory-pathname path)))))

(defun benchmark-filesystem (directory)
  (let ((existing (merge-pathnames "src/strings.lisp" (checkout-root))))
    (benchmark-case
      "truenamize existing"
      10
      (lambda ()
        (host-kit:truenamize existing))))
  (dolist (depth (quote (1 10 50)))
    (let ((missing (merge-pathnames (relative-path depth) directory))
          (operations
          (if (= depth 50) 1
            10))
          (maximum-operations
          (if (= depth 50) 10
            50)))
      (benchmark-case
        (format nil "truenamize missing/~D" depth)
        operations
        (lambda ()
          (host-kit:truenamize missing))
        :maximum-operations
        maximum-operations)))
  (dolist (bytes (quote (1024 65536)))
    (let ((ascii (merge-pathnames (format nil "ascii-~D.txt" bytes) directory))
          (utf8 (merge-pathnames (format nil "utf8-~D.txt" bytes) directory))
          (operations
          (if (= bytes 65536) 10
            100))
          (maximum-operations
          (if (= bytes 65536) 50
            500)))
      (write-ascii-file ascii bytes)
      (write-utf8-file utf8 bytes)
      (benchmark-case
        (format nil "read ASCII/~DKiB" (/ bytes 1024))
        operations
        (lambda ()
          (host-kit:read-file-string ascii))
        :maximum-operations
        maximum-operations)
      (benchmark-case
        (format nil "read UTF-8/~DKiB" (/ bytes 1024))
        operations
        (lambda ()
          (host-kit:read-file-string utf8))
        :maximum-operations
        maximum-operations)
      (when (= bytes 1024)
        (benchmark-comparison
          "read ASCII/1KiB"
          operations
          (lambda ()
            (host-kit:read-file-string ascii))
          (lambda ()
            (uiop:read-file-string ascii))
          :maximum-operations
          maximum-operations)
        (benchmark-comparison
          "read UTF-8/1KiB"
          operations
          (lambda ()
            (host-kit:read-file-string utf8))
          (lambda ()
            (uiop:read-file-string utf8))
          :maximum-operations
          maximum-operations)))))

(defparameter +benchmark-groups+ (quote ("splits" "pathnames" "filesystem")))

(defun selected-benchmark-p (name)
  (let ((requested (host-kit:getenv "CL_HOST_KIT_BENCHMARK")))
    (when (and
        requested
        (not (member requested +benchmark-groups+ :test (function string=))))
      (error "Unknown CL_HOST_KIT_BENCHMARK value: ~S" requested))
    (or (null requested) (string= requested name))))

(defun main ()
  (format
    t
    "cl-host-kit microbench: ~D warmups, ~D measured samples~%"
    +warmup-samples+
    +measured-samples+)
  (finish-output)
  (let ((directory (temporary-directory)))
    (unwind-protect (progn
        (when (selected-benchmark-p "splits")
          (benchmark-splits))
        (when (selected-benchmark-p "pathnames")
          (benchmark-pathnames))
        (when (selected-benchmark-p "filesystem")
          (benchmark-filesystem directory)))
      (host-kit:delete-directory-tree directory :validate t)))
  (format t "sink: ~D~%" *benchmark-sink*))

(main)
