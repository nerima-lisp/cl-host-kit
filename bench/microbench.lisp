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

(progn
  (defun benchmark-environment-number (name default parser)
    (let ((value (sb-ext:posix-getenv name)))
      (if (and value (plusp (length value)))
          (let ((parsed (ignore-errors (funcall parser value))))
            (if (and parsed (plusp parsed))
                parsed
                (error "Invalid positive benchmark setting ~A=~S." name value)))
          default)))
  (defparameter +warmup-samples+
    (benchmark-environment-number
      "CL_HOST_KIT_BENCH_WARMUPS" 3 (function parse-integer))))

(progn
  (defparameter +measured-samples+
    (benchmark-environment-number
      "CL_HOST_KIT_BENCH_SAMPLES" 16 (function parse-integer)))
  (unless (evenp +measured-samples+)
    (error "CL_HOST_KIT_BENCH_SAMPLES must be even for balanced ABBA ordering, got ~D."
           +measured-samples+)))

(defparameter *benchmark-sink* 0)

(unless (find-package (quote #:host-kit))
  (require :asdf)
  (funcall (symbol-function (find-symbol "LOAD-SYSTEM" :asdf)) "cl-host-kit"))

(progn
  (defun median (values)
    (let* ((sorted (sort (copy-seq values) #'<))
           (middle (floor (length sorted) 2)))
      (if (oddp (length sorted))
          (elt sorted middle)
          (/ (+ (elt sorted (1- middle)) (elt sorted middle)) 2))))
  (defun percentile (values fraction)
    (let* ((sorted (sort (copy-seq values) #'<))
           (index (round (* fraction (1- (length sorted))))))
      (elt sorted index)))
  (defun median-absolute-deviation (values)
    (let ((center (median values)))
      (median (map 'vector (lambda (value) (abs (- value center))) values))))
  (defun print-raw-samples (name elapsed bytes)
  (format t "~&~A raw us/op: ~{~,3F~^, ~}~%"
          name (map (quote list) (lambda (value) (* 1000000.0 value)) elapsed))
  (format t "~&~A raw B/op: ~{~,1F~^, ~}~%"
          name (coerce bytes (quote list)))
  (loop for sample below (length elapsed)
        do (format t "RAW~C~A~C~D~C~,9F~C~,1F~%"
                   #\Tab name #\Tab sample #\Tab (aref elapsed sample)
                   #\Tab (aref bytes sample))))
  (defun print-throughput (payload-bytes seconds-per-operation)
    (when payload-bytes
      (format t ", ~,1F MiB/s"
              (/ payload-bytes seconds-per-operation 1048576.0)))))

(defun consume-result (value)
  (setf *benchmark-sink* (logxor *benchmark-sink* (sxhash value))))

(defun measure-sample (operations function)
  (let ((result nil)
        (start-time (get-internal-real-time))
        (start-bytes (sb-ext:get-bytes-consed)))
    (dotimes (index operations)
      (declare (ignore index))
      (setf result (funcall function)))
    (let ((end-time (get-internal-real-time))
          (end-bytes (sb-ext:get-bytes-consed)))
      (consume-result result)
      (values
        (/ (- end-time start-time)
           internal-time-units-per-second
           operations)
        (/ (- end-bytes start-bytes) operations)))))

(progn
  (defun read-benchmark-number (value)
    (let ((*read-eval* nil))
      (multiple-value-bind (number end)
          (read-from-string value nil nil)
        (unless (and number
                     (loop for index from end below (length value)
                           always (member (char value index)
                                          (quote (#\Space #\Tab #\Newline #\Return)))))
          (error "Benchmark number contains trailing content: ~S" value))
        number)))
  (defparameter +calibration-target-seconds+
    (benchmark-environment-number
      "CL_HOST_KIT_BENCH_SAMPLE_SECONDS"
      0.1d0
      (lambda (value)
        (coerce (read-benchmark-number value) (quote double-float))))))

(defparameter +maximum-calibration-operations+
  (benchmark-environment-number
    "CL_HOST_KIT_BENCH_MAX_OPERATIONS" 1000000 (function parse-integer)))

(defun calibrated-operations (name minimum-operations maximum-operations function)
  (loop with operations = minimum-operations
        do (multiple-value-bind (seconds-per-operation bytes-per-operation)
               (measure-sample operations function)
             (declare (ignore bytes-per-operation))
             (let ((total-seconds (* seconds-per-operation operations)))
               (cond
                 ((>= total-seconds +calibration-target-seconds+)
                  (return operations))
                 ((>= operations maximum-operations)
                  (when (zerop total-seconds)
                    (error "~A calibration measured zero elapsed time at the ~:D-operation cap. Increase CL_HOST_KIT_BENCH_MAX_OPERATIONS or the case-specific cap."
                           name operations))
                  (format *error-output*
                          "WARNING: ~A calibration reached the ~:D-operation cap at ~,3F ms (target ~,3F ms).~%"
                          name
                          operations
                          (* 1000 total-seconds)
                          (* 1000 +calibration-target-seconds+))
                  (finish-output *error-output*)
                  (return operations))
                 (t
                  (setf operations
                        (min maximum-operations (* 2 operations)))))))))

(defun benchmark-case (name operations function
                       &key
                         (maximum-operations +maximum-calibration-operations+)
                         payload-bytes)
  (format t "~&Running ~A...~%" name)
  (finish-output)
  (let ((operations (calibrated-operations
                      name operations maximum-operations function)))
    (sb-ext:gc :full t)
    (dotimes (sample +warmup-samples+)
      (declare (ignore sample))
      (measure-sample operations function))
    (sb-ext:gc :full t)
    (let ((elapsed (make-array +measured-samples+))
          (bytes (make-array +measured-samples+)))
      (dotimes (sample +measured-samples+)
        (multiple-value-bind (sample-elapsed sample-bytes)
            (measure-sample operations function)
          (when (zerop sample-elapsed)
            (error "~A measured zero elapsed time for ~:D operations; increase CL_HOST_KIT_BENCH_MAX_OPERATIONS."
                   name operations))
          (setf (aref elapsed sample) sample-elapsed
                (aref bytes sample) sample-bytes)))
      (let* ((seconds-per-operation (median elapsed))
             (microseconds (* 1000000.0 seconds-per-operation))
             (bytes-per-operation (median bytes)))
        (format t "~&~A (~D ops): ~,2F us/op, ~,1F B/op"
                name operations microseconds bytes-per-operation)
        (print-throughput payload-bytes seconds-per-operation)
        (terpri)
        (print-raw-samples name elapsed bytes)
        (finish-output)
        (values microseconds bytes-per-operation)))))

(defun benchmark-comparison (name operations host-function reference-function
                             &key
                               (maximum-operations
                                 +maximum-calibration-operations+)
                               (result-test (function equalp))
                               (reference-label "UIOP")
                               payload-bytes)
  (unless (funcall result-test (funcall host-function) (funcall reference-function))
    (error "Benchmark comparison ~A has incompatible results." name))
  (let* ((host-name (format nil "~A host-kit" name))
         (reference-name (format nil "~A ~A" name reference-label))
         (host-calibration
           (calibrated-operations
             host-name operations maximum-operations host-function))
         (reference-calibration
           (calibrated-operations
             reference-name operations maximum-operations reference-function))
         (sample-operations (max host-calibration reference-calibration))
         (host-elapsed (make-array +measured-samples+))
         (host-bytes (make-array +measured-samples+))
         (reference-elapsed (make-array +measured-samples+))
         (reference-bytes (make-array +measured-samples+)))
    (format t "~&Running ~A and ~A with paired ABBA order (~D ops each)...~%"
            host-name reference-name sample-operations)
    (finish-output)
    (labels ((run (function)
               (measure-sample sample-operations function))
             (record (sample function elapsed bytes)
               (multiple-value-bind (seconds allocation) (run function)
                 (when (zerop seconds)
                   (error "~A measured zero elapsed time for ~:D operations; increase CL_HOST_KIT_BENCH_MAX_OPERATIONS."
                          name sample-operations))
                 (setf (aref elapsed sample) seconds
                       (aref bytes sample) allocation)))
             (run-pair (sample recordp)
               (flet ((one (function elapsed bytes)
                        (sb-ext:gc :full t)
                        (if recordp
                            (record sample function elapsed bytes)
                            (run function))))
                 (if (evenp sample)
                     (progn
                       (one host-function host-elapsed host-bytes)
                       (one reference-function reference-elapsed reference-bytes))
                     (progn
                       (one reference-function reference-elapsed reference-bytes)
                       (one host-function host-elapsed host-bytes))))))
      (dotimes (sample +warmup-samples+)
        (run-pair sample nil))
      (dotimes (sample +measured-samples+)
        (run-pair sample t)))
    (let* ((host-seconds (median host-elapsed))
           (reference-seconds (median reference-elapsed))
           (host-allocation (median host-bytes))
           (reference-allocation (median reference-bytes))
           (time-ratios (map (quote vector) (function /)
                             host-elapsed reference-elapsed))
           (allocation-ratios
             (unless (find 0 reference-bytes)
               (map (quote vector) (function /) host-bytes reference-bytes))))
      (format t "~&~A (~D ops): ~,2F us/op, ~,1F B/op"
              host-name sample-operations (* 1000000.0 host-seconds) host-allocation)
      (print-throughput payload-bytes host-seconds)
      (terpri)
      (format t "~&~A (~D ops): ~,2F us/op, ~,1F B/op"
              reference-name sample-operations
              (* 1000000.0 reference-seconds) reference-allocation)
      (print-throughput payload-bytes reference-seconds)
      (terpri)
      (print-raw-samples host-name host-elapsed host-bytes)
      (print-raw-samples reference-name reference-elapsed reference-bytes)
      (format t "~&~A paired time ratio host/~A: median ~,3Fx, MAD ~,3F, p10 ~,3F, p90 ~,3F~%"
              name reference-label (median time-ratios)
              (median-absolute-deviation time-ratios)
              (percentile time-ratios 0.1) (percentile time-ratios 0.9))
      (if allocation-ratios
          (format t "~A paired allocation ratio host/~A: median ~,3Fx, MAD ~,3F, p10 ~,3F, p90 ~,3F (< 1 is lower)~%"
                  name reference-label (median allocation-ratios)
                  (median-absolute-deviation allocation-ratios)
                  (percentile allocation-ratios 0.1)
                  (percentile allocation-ratios 0.9))
          (format t "~A paired allocation ratio: N/A (~A reported zero in at least one sample)~%"
                  name reference-label))
      (finish-output))))

(defun repeated-string (character count)
  (make-string count :initial-element character))

(defun split-input ()
  (with-output-to-string (stream)
    (dotimes (field 100)
      (declare (ignore field))
      (write-string "token," stream))))

(progn
  (defun linear-split-string-reference (string separator)
    (let ((start 0)
          (segments (quote ())))
      (loop for index below (length string)
            when (find (char string index) separator)
              do (push (subseq string start index) segments)
                 (setf start (1+ index)))
      (nreverse (cons (subseq string start) segments))))
  (defun separator-string (width)
    (let ((separator (make-string width)))
      (dotimes (index width separator)
        (setf (char separator index)
              (if (zerop index)
                  #\,
                  (or (code-char (+ (if (>= width 64) #x2000 65) index))
                      (error "Cannot construct separator character ~D." index))))))))

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

(progn
  (defun split-density-input (length period)
    (let ((input (make-string length :initial-element #\a)))
      (when period
        (loop for index from (1- period) below length by period
              do (setf (char input index) #\,)))
      input))
  (defun assert-split-edge-semantics ()
    (assert (equal (host-kit:split-string "" :separator #\,) (list "")))
    (assert (equal (host-kit:split-string ",a," :separator #\,) (list "" "a" "")))
    (assert (equal (host-kit:split-string "a,b,c" :separator #\, :max 1)
                   (list "a,b,c")))
    (assert (equal (host-kit:split-string "a,b,c" :separator #\, :max 2)
                   (list "a" "b,c"))))
  (defun benchmark-split-reference-case (name input separator)
    (benchmark-comparison
      name
      1
      (lambda () (host-kit:split-string input :separator separator))
      (lambda () (linear-split-string-reference input separator))
      :reference-label "linear-old"
      :payload-bytes (length input)))
  (defun benchmark-splits ()
    (assert-split-edge-semantics)
    (dolist (spec (quote (("empty/char" 0 nil 1)
                          ("boundary-27/separator-8" 27 4 8)
                          ("boundary-28/separator-8" 28 4 8)
                          ("boundary-29/separator-9" 29 4 9)
                          ("sparse-1KiB/separator-16" 1024 128 16)
                          ("dense-1KiB/separator-16" 1024 2 16)
                          ("absent-8KiB/separator-64" 8192 nil 64)
                          ("sparse-8KiB/separator-64" 8192 64 64)
                          ("sparse-1MiB/separator-64" 1048576 256 64))))
      (destructuring-bind (name length period width) spec
        (let* ((input (split-density-input length period))
               (separator (separator-string width)))
          (benchmark-split-reference-case
           (format nil "split matrix/~A" name) input separator))))
    (let ((input (split-input)))
      (benchmark-comparison
       "split char/UIOP"
       1
       (lambda () (host-kit:split-string input :separator #\,))
       (lambda () (uiop:split-string input :separator ","))
       :payload-bytes (length input)))))
(defun stream-join-strings (strings &key (separator ""))
  (with-output-to-string (output)
    (etypecase strings
      (list
        (loop with firstp = t
              for string in strings
              do (unless firstp
                   (write-string separator output))
                 (check-type string string)
                 (write-string string output)
                 (setf firstp nil)))
      (vector
        (loop with firstp = t
              for string across strings
              do (unless firstp
                   (write-string separator output))
                 (check-type string string)
                 (write-string string output)
                 (setf firstp nil))))))
(defun benchmark-join-case (name strings separator)
  (benchmark-comparison
    (format nil "join ~A" name)
    1
    (lambda ()
      (host-kit:join-strings strings :separator separator))
    (lambda ()
      (stream-join-strings strings :separator separator))
    :reference-label "stream"))
(defun benchmark-joins ()
  (dolist (spec (quote (("empty" 0 0 "")
                        ("single" 1 16 ",")
                        ("small" 8 8 ",")
                        ("medium" 100 16 ",")
                        ("large-elements" 100 1024 "::"))))
    (destructuring-bind (name count width separator) spec
      (let* ((list-input
              (loop repeat count collect (repeated-string #\a width)))
             (vector-input (coerce list-input (quote vector))))
        (benchmark-join-case (format nil "~A/list" name) list-input separator)
        (benchmark-join-case (format nil "~A/vector" name) vector-input separator)))))

(progn
  (defun pathname-within-old-reference (pathspec directory)
    (let* ((pathname (host-kit:ensure-absolute-pathname pathspec))
           (directory
             (host-kit:ensure-directory-pathname
               (host-kit:ensure-absolute-pathname directory)))
           (pathname-directory
             (host-kit:pathname-directory-pathname pathname))
           (pathname-components
             (host-kit::%normalized-absolute-directory-components
               pathname-directory))
           (directory-components
             (host-kit::%normalized-absolute-directory-components directory)))
      (and (equal (pathname-host pathname-directory)
                  (pathname-host directory))
           (equal (pathname-device pathname-directory)
                  (pathname-device directory))
           (<= (length directory-components) (length pathname-components))
           (equal directory-components
                  (subseq pathname-components
                          0
                          (length directory-components))))))
  (defun benchmark-pathnames ()
    (dolist (depth (quote (1 10 50)))
      (let* ((path (relative-path depth))
             (directory
               (merge-pathnames
                 (host-kit:ensure-directory-pathname path)
                 (checkout-root)))
             (child (merge-pathnames "child.txt" directory)))
        (benchmark-case
          (format nil "ensure-directory/~D" depth)
          100
          (lambda ()
            (host-kit:ensure-directory-pathname path)))
        (benchmark-case
          (format nil "ensure-absolute/~D" depth)
          100
          (lambda ()
            (host-kit:ensure-absolute-pathname path)))
        (benchmark-comparison
          (format nil "pathname-within/~D" depth)
          100
          (lambda ()
            (host-kit:pathname-within-p child directory))
          (lambda ()
            (pathname-within-old-reference child directory))
          :reference-label "subseq-old")))
    (let ((path (relative-path 10)))
      (benchmark-comparison
        "ensure-directory/10"
        100
        (lambda ()
          (host-kit:ensure-directory-pathname path))
        (lambda ()
          (uiop:ensure-directory-pathname path))))))
(progn
  (defun validate-environment-bindings-old-reference (bindings)
    (check-type bindings list)
    (unless (list-length bindings)
      (error (quote type-error) :datum bindings :expected-type (quote list)))
    (loop with names = (quote ())
          for binding in bindings
          for normalized = (host-kit::%validate-environment-binding binding)
          for name = (first normalized)
          do (when (find name names :test (function string=))
               (error (quote type-error)
                      :datum bindings
                      :expected-type (quote list)))
             (push name names)
          collect normalized))
  (defun benchmark-environment ()
    (let ((bindings
            (loop for index below 256
                  collect (list (format nil "CL_HOST_KIT_BENCH_~D" index)
                                "value"))))
      (benchmark-comparison
        "environment dedup/256"
        1
        (lambda ()
          (host-kit::%validate-environment-bindings bindings))
        (lambda ()
          (validate-environment-bindings-old-reference bindings))
        :reference-label "linear-old")))
  (defun benchmark-find-program ()
    (let* ((missing-directories
             (loop for index below 64
                   collect (format nil "/cl-host-kit-missing-~D" index)))
           (missing-path
             (host-kit:join-strings missing-directories :separator ":"))
           (first-path (format nil "/bin:~A" missing-path))
           (last-path (format nil "~A:/bin" missing-path)))
      (benchmark-case
        "find-program first/64-tail"
        10
        (lambda ()
          (host-kit:find-program "sh" :path first-path)))
      (benchmark-case
        "find-program last/64-head"
        1
        (lambda ()
          (host-kit:find-program "sh" :path last-path))))))

(progn
  (defun append-octet-buffer-old-reference (contents size buffer end)
    (let* ((required-size (+ size end))
           (contents
             (if (<= required-size (array-total-size contents))
                 contents
                 (adjust-array
                   contents
                   (max required-size
                        (* 2 (array-total-size contents)))))))
      (replace contents buffer :start1 size :end1 required-size :end2 end)
      (values contents required-size)))
  (defun read-octet-stream-old-reference (stream)
    (let ((buffer
            (make-array 65536 :element-type (quote (unsigned-byte 8))))
          (contents
            (make-array 65536
                        :element-type (quote (unsigned-byte 8))
                        :adjustable t))
          (size 0))
      (loop for end = (read-sequence buffer stream)
            while (plusp end)
            do (multiple-value-setq (contents size)
                 (append-octet-buffer-old-reference
                   contents size buffer end)))
      (adjust-array contents size)))
  (defun read-file-octets-old-reference (path)
    (with-open-file (stream path
                            :direction :input
                            :element-type (quote (unsigned-byte 8)))
      (read-octet-stream-old-reference stream)))
  (defun directory-tree-two-stat-old-reference (directory)
    (let ((metadata (host-kit:file-metadata directory)))
      (unless (eq (host-kit:file-metadata-kind metadata) :directory)
        (error "~S does not denote a directory" directory)))
    (host-kit:call-with-directory-tree
      (lambda (entry metadata depth)
        (declare (ignore entry metadata depth)))
      directory
      :max-depth 0))
  (defun benchmark-filesystem (directory)
    (let ((existing (merge-pathnames "src/strings.lisp" (checkout-root))))
      (benchmark-case
        "truenamize existing"
        10
        (lambda ()
          (host-kit:truenamize existing))))
    (dolist (depth (quote (1 10 50)))
      (let ((missing (merge-pathnames (relative-path depth) directory))
            (operations (if (= depth 50) 1 10)))
        (benchmark-case
          (format nil "truenamize missing/~D" depth)
          operations
          (lambda ()
            (host-kit:truenamize missing)))))
    (dolist (bytes (quote (1024 65536)))
      (let ((ascii
              (merge-pathnames (format nil "ascii-~D.txt" bytes) directory))
            (utf8
              (merge-pathnames (format nil "utf8-~D.txt" bytes) directory))
            (operations (if (= bytes 65536) 10 100)))
        (write-ascii-file ascii bytes)
        (write-utf8-file utf8 bytes)
        (benchmark-case
          (format nil "read ASCII/~DKiB" (/ bytes 1024))
          operations
          (lambda ()
            (host-kit:read-file-string ascii))
          :payload-bytes bytes)
        (benchmark-case
          (format nil "read UTF-8/~DKiB" (/ bytes 1024))
          operations
          (lambda ()
            (host-kit:read-file-string utf8))
          :payload-bytes bytes)
        (when (= bytes 1024)
          (benchmark-comparison
            "read ASCII/1KiB"
            operations
            (lambda ()
              (host-kit:read-file-string ascii))
            (lambda ()
              (uiop:read-file-string ascii))
            :payload-bytes bytes)
          (benchmark-comparison
            "read UTF-8/1KiB"
            operations
            (lambda ()
              (host-kit:read-file-string utf8))
            (lambda ()
              (uiop:read-file-string utf8))
            :payload-bytes bytes))))
    (let* ((bytes 1048576)
           (path (merge-pathnames "octets-1048576.bin" directory))
           (octets
             (make-array bytes
                         :element-type (quote (unsigned-byte 8))
                         :initial-element 42)))
      (setf (aref octets (1- bytes)) 255)
      (host-kit:write-file-octets octets path)
      (benchmark-comparison
        "read octets/exact-1MiB"
        1
        (lambda ()
          (host-kit:read-file-octets path))
        (lambda ()
          (read-file-octets-old-reference path))
        :reference-label "buffer-old"
        :payload-bytes bytes))
    (benchmark-comparison
      "directory root metadata"
      1
      (lambda ()
        (host-kit:call-with-directory-tree
          (lambda (entry metadata depth)
            (declare (ignore entry metadata depth)))
          directory
          :max-depth 0))
      (lambda ()
        (directory-tree-two-stat-old-reference directory))
      :reference-label "two-stat-old")))

(defparameter +benchmark-groups+
  (quote ("splits" "joins" "pathnames" "environment" "process" "filesystem")))

(defun selected-benchmark-p (name)
  (let ((requested (host-kit:getenv "CL_HOST_KIT_BENCHMARK")))
    (when (and
        requested
        (not (member requested +benchmark-groups+ :test (function string=))))
      (error "Unknown CL_HOST_KIT_BENCHMARK value: ~S" requested))
    (or (null requested) (string= requested name))))

(defun main ()
  (format t "cl-host-kit microbench: ~D warmups, ~D measured samples~%"
          +warmup-samples+ +measured-samples+)
  (finish-output)
  (let ((directory (temporary-directory)))
    (unwind-protect
         (progn
           (when (selected-benchmark-p "splits")
             (benchmark-splits))
           (when (selected-benchmark-p "joins")
             (benchmark-joins))
           (when (selected-benchmark-p "pathnames")
             (benchmark-pathnames))
           (when (selected-benchmark-p "environment")
             (benchmark-environment))
           (when (selected-benchmark-p "process")
             (benchmark-find-program))
           (when (selected-benchmark-p "filesystem")
             (benchmark-filesystem directory)))
      (host-kit:delete-directory-tree directory :validate t)))
  (format t "sink: ~D~%" *benchmark-sink*))

(main)
