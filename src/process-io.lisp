;;;; src/process-io.lisp
;;;;
;;;; The concurrent capture/production engine RUN-PROGRAM's process.lisp
;;;; orchestrates: draining a child's stdout/stderr on dedicated threads while
;;;; the caller may still be feeding its stdin.
(in-package #:host-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

(defstruct (%output-capture (:constructor %make-output-capture))
  stream
  owner
  thread
  (truncated-p nil)
  (abandoned-p nil)
  (stop-requested-p nil)
  condition)

(defvar *active-output-captures* nil)
(defvar *active-output-captures-lock*
  (sb-thread:make-mutex :name "cl-host-kit active output captures"))

(defun %register-output-capture (capture)
  (sb-thread:with-mutex (*active-output-captures-lock*)
    (push capture *active-output-captures*))
  capture)

(defun %unregister-output-capture (capture)
  (sb-thread:with-mutex (*active-output-captures-lock*)
    (setf *active-output-captures*
          (delete capture *active-output-captures* :test (function eq)))))

(defun %record-output-capture-condition (capture condition)
  (sb-thread:with-mutex (*active-output-captures-lock*)
    (setf (%output-capture-condition capture) condition)))

(defun %output-capture-failed-p (owner)
  (sb-thread:with-mutex (*active-output-captures-lock*)
    (some (lambda (capture)
            (and (eq (%output-capture-owner capture) owner)
                 (%output-capture-condition capture)))
          *active-output-captures*)))

(defun %start-output-capture (stream limit name &optional consumer)
  (let ((sink (make-string-output-stream))
        (capture nil)
        (count 0)
        (fd (sb-sys:fd-stream-fd stream)))
    (labels ((capture-character ()
               (let ((character (read-char stream nil nil)))
                 (unless character
                   (return-from capture-character))
                 (if consumer (funcall consumer character)
                     (if (< count limit) (progn
                                          (write-char character sink)
                                          (incf count))
                         (setf (%output-capture-truncated-p capture) t)))
                 t)))
      (setf capture (%make-output-capture :stream stream :owner sb-thread:*current-thread*))
      (%register-output-capture capture)
      (setf (%output-capture-thread capture) (sb-thread:make-thread
          (lambda ()
            (handler-case (loop (cond
                                  ((listen stream)
                                   (unless (capture-character)
                                     (return)))
                                  ((%output-capture-stop-requested-p capture) (return))
                                  ((sb-sys:wait-until-fd-usable fd :input 0.02d0)
                                   (unless (capture-character)
                                     (return)))))
              (error (condition)
                (%record-output-capture-condition capture condition))))
          :name name))
      (values capture sink))))

(defun %finish-output-capture (capture sink)
  (unwind-protect
       (let ((thread (%output-capture-thread capture)))
         ;; A descendant can retain this descriptor after its direct parent exits.
         (when (eq (sb-thread:join-thread thread
                                          :timeout 0.05d0
                                          :default :timed-out)
                   :timed-out)
           (setf (%output-capture-abandoned-p capture) t
                 (%output-capture-stop-requested-p capture) t)
           ;; The capture loop polls its descriptor, so this wait is bounded too.
           (sb-thread:join-thread thread :timeout 0.1d0 :default :timed-out))
         (ignore-errors (close (%output-capture-stream capture)))
         (let ((condition (%output-capture-condition capture)))
           (when (and condition (not (%output-capture-abandoned-p capture)))
             (error condition)))
         (get-output-stream-string sink))
    (%unregister-output-capture capture)))

(defstruct (%input-producer (:constructor %make-input-producer)) stream
  thread
  condition)

(defun %start-input-producer (stream writer)
  (let ((producer (%make-input-producer :stream stream)))
    (setf (%input-producer-thread producer) (sb-thread:make-thread
        (lambda ()
          (unwind-protect (handler-case (funcall writer stream)
              (error (condition)
                (setf (%input-producer-condition producer) condition)))
            (ignore-errors (close stream))))
        :name
        "cl-host-kit program input"))
    producer))

(defun %finish-input-producer (producer &key (timeout 0.1d0))
  "Close PRODUCER input and wait at most TIMEOUT seconds for its worker.
The caller cannot safely terminate arbitrary Common Lisp code, so an input
callback that ignores its closed stream is detached after this bounded grace."
  (when producer
    (ignore-errors (close (%input-producer-stream producer)))
    (unless (eq
        (sb-thread:join-thread
          (%input-producer-thread producer)
          :timeout
          timeout
          :default
          :timed-out)
        :timed-out)
      (%input-producer-condition producer))))
