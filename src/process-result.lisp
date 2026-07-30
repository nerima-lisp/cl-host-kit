;;;; src/process-result.lisp
;;;;
;;;; The process data model (PROCESS-RESULT and its exit-code contract) and
;;;; PATH-based program lookup -- everything about locating and describing a
;;;; process, as opposed to running one.
(in-package #:host-kit)

(defconstant +default-command-timeout-seconds+ 30d0
  "Default wall-clock timeout used by RUN-PROGRAM.")

(defconstant +default-command-output-limit+ (* 1024 1024))

(defstruct process-result "Terminal data captured by RUN-PROGRAM. A non-zero EXIT-CODE is data, not
an error; TIMEOUT is reported separately by PROCESS-TIMEOUT."
  program
  arguments
  exit-code
  signal
  (stdout "" :type string)
  (stderr "" :type string)
  timed-out-p
  stdout-truncated-p
  stderr-truncated-p)

(defun %validate-expected-exit-codes (expected-exit-codes)
  (check-type expected-exit-codes list)
  (let ((exit-code-count (list-length expected-exit-codes)))
    (unless (and exit-code-count (plusp exit-code-count))
      (error
        (quote type-error)
        :datum
        expected-exit-codes
        :expected-type
        (quote list))))
  (dolist (exit-code expected-exit-codes)
    (check-type exit-code (integer 0 *)))
  expected-exit-codes)

(defun ensure-program-success (result &key (expected-exit-codes '(0)))
  "Return RESULT when its exit code is expected, otherwise signal PROCESS-EXIT-ERROR.
EXPECTED-EXIT-CODES is a list of non-negative integer exit codes."
  (check-type result process-result)
  (%validate-expected-exit-codes expected-exit-codes)
  (unless (member (process-result-exit-code result) expected-exit-codes)
    (error
      'process-exit-error
      :program
      (process-result-program result)
      :arguments
      (process-result-arguments result)
      :exit-code
      (process-result-exit-code result)
      :signal
      (process-result-signal result)
      :expected-exit-codes
      expected-exit-codes
      :result
      result))
  result)

(defun %colon-separated-directories (path)
  "Split PATH on #\\: into a list of substrings, preserving empty elements."
  (loop with start = 0
        for colon = (position #\: path :start start)
        collect (subseq path start colon)
        while colon
        do (setf start (1+ colon))))

(defun find-program (program &key (path (getenv "PATH")))
  "Return the executable pathname for PROGRAM, or NIL when none is found.
PROGRAM may be an explicit path or a bare file name. Bare names are searched
through the colon-separated PATH string; an empty PATH element denotes the
current directory."
  (check-type program string)
  (check-type path (or null string))
  (cond
    ((find #\/ program)
     (file-executable-p program))
    ((null path) nil)
    (t
     (loop for directory in (%colon-separated-directories path)
           for candidate = (merge-pathnames program
                                            (if (string= directory "")
                                                (ensure-directory-pathname
                                                 (sb-posix:getcwd))
                                                (ensure-directory-pathname directory)))
           for executable = (file-executable-p candidate)
           when executable return executable))))
