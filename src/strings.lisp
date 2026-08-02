;;;; src/strings.lisp
;;;;
;;;; String helpers, scoped to exactly how the rest of nerima-lisp calls them
;;;; today (see the org-wide call-site survey in the design notes):
;;;; SPLIT-STRING accepts :MAX because upstream UIOP does, and its :SEPARATOR
;;;; is always a bag of individual delimiter characters (a list of characters,
;;;; or a string treated as one), never a multi-character delimiter sequence.
;;;; STRING-PREFIX-P/STRING-SUFFIX-P are the plain two-argument predicates.
(in-package #:host-kit)

(defmacro %split-string-when ((string separator character remaining) delimiter-p)
  "Expand the shared scan used by SPLIT-STRING separator specializations.
REMAINING is an expression for the number of splits still permitted, or NIL
for no limit."
  (let ((segments (gensym "SEGMENTS"))
        (start (gensym "START"))
        (index (gensym "INDEX"))
        (remaining-count (gensym "REMAINING")))
    `(let ((,string ,string)
          (,separator ,separator)
          (,segments nil)
          (,start 0)
          (,remaining-count ,remaining))
      (declare (type string ,string)
               (type fixnum ,start)
               (type (or null fixnum) ,remaining-count)
               (optimize (speed 3) (safety 1) (debug 0)))
      (loop for ,index fixnum from 0 below (length ,string)
            for ,character = (char ,string ,index)
            when (and ,delimiter-p (or (null ,remaining-count) (plusp ,remaining-count)))
              do (push (subseq ,string ,start ,index) ,segments)
                 (setf ,start (1+ ,index))
                 (when ,remaining-count
                   (decf ,remaining-count)
                   (when (zerop ,remaining-count) (loop-finish))))
      (push (subseq ,string ,start) ,segments)
      (nreverse ,segments))))

(progn
  (declaim (inline %split-string-linear))
  (defun %split-string-linear (string separator-string remaining-splits)
    (%split-string-when (string separator-string character remaining-splits)
      (find character separator-string))))

(defun %separator-code-bounds (separator-string)
  (let ((minimum-code (char-code (char separator-string 0)))
        (maximum-code (char-code (char separator-string 0))))
    (loop for separator-character across separator-string
          for code = (char-code separator-character)
          do (setf minimum-code (min minimum-code code)
                   maximum-code (max maximum-code code)))
    (values minimum-code maximum-code)))

(defun %split-string-bitmap
    (string separator-string remaining-splits minimum-code maximum-code)
  (let* ((span (1+ (- maximum-code minimum-code)))
         (separator-bitmap
           (make-array span :element-type (quote bit) :initial-element 0)))
    (loop for separator-character across separator-string
          do (setf (sbit separator-bitmap
                         (- (char-code separator-character) minimum-code))
                   1))
    (%split-string-when
        (string separator-bitmap character remaining-splits)
      (let ((offset (- (char-code character) minimum-code)))
        (and (<= 0 offset)
             (< offset span)
             (= 1 (sbit separator-bitmap offset)))))))

(defun %split-string-hash (string separator-string remaining-splits)
  (let ((separator-table
          (make-hash-table :test (function eql)
                           :size (length separator-string))))
    (loop for separator-character across separator-string
          do (setf (gethash separator-character separator-table) t))
    (%split-string-when (string separator-table character remaining-splits)
      (gethash character separator-table))))

(progn
  (declaim (inline %split-string-character-set))
  (defun %split-string-character-set
      (string separator-string remaining-splits)
    (if (or (<= (length separator-string) 8)
            (< (length string)
               (ceiling 256 (length separator-string))))
        (%split-string-linear string separator-string remaining-splits)
        (multiple-value-bind (minimum-code maximum-code)
            (%separator-code-bounds separator-string)
          (if (<= (1+ (- maximum-code minimum-code)) 4096)
              (%split-string-bitmap string
                                    separator-string
                                    remaining-splits
                                    minimum-code
                                    maximum-code)
              (%split-string-hash string
                                  separator-string
                                  remaining-splits))))))

(defun split-string (string &key (separator #\Space) max)
  "Split STRING wherever any character in SEPARATOR (a list of characters, a string of characters, or a single character) appears, treating each separator character as an independent one-character delimiter. Consecutive separator characters produce empty-string segments between them, matching the behavior response-file and line-oriented callers in this org rely on.

When MAX is supplied, split at most CEILING(MAX) - 1 times and keep the remaining substring as the final segment."
  (check-type string string)
  (let ((remaining-splits
          (and max
               (min (length string)
                    (max 0 (1- (ceiling max)))))))
    (flet ((scan-character (separator-character)
             (declare (type character separator-character))
             (%split-string-when
                 (string separator-character character remaining-splits)
               (char= character separator-character))))
      (etypecase separator
        (character
         (scan-character separator))
        (string
         (let ((separator-length (length separator)))
           (cond
             ((zerop separator-length)
              (list (copy-seq string)))
             ((= separator-length 1)
              (scan-character (char separator 0)))
             (t
              (%split-string-character-set
               string separator remaining-splits)))))
        (list
         (cond
           ((endp separator)
            (list (copy-seq string)))
           ((endp (cdr separator))
            (let ((separator-character (car separator)))
              (check-type separator-character character)
              (scan-character separator-character)))
           (t
            (let ((separator-string (make-string (length separator))))
              (loop for separator-character in separator
                    for index fixnum from 0
                    do (check-type separator-character character)
                       (setf (char separator-string index)
                             separator-character))
              (%split-string-character-set
               string separator-string remaining-splits)))))))))

(defun string-prefix-p (prefix string)
  "True when STRING starts with PREFIX."
  (declare (type string prefix string)
           (optimize (speed 3) (safety 1) (debug 0)))
  (let ((prefix-length (length prefix)))
    (and
      (<= prefix-length (length string))
      (string= prefix string :end2 prefix-length))))

(defun string-suffix-p (suffix string)
  "True when STRING ends with SUFFIX."
  (let ((suffix-length (length suffix))
        (string-length (length string)))
    (and (<= suffix-length string-length)
         (string= suffix string :start2 (- string-length suffix-length)))))

(defun %join-string-list (strings separator separator-length)
  (let ((count 0)
        (content-length 0))
    (dolist (string strings)
      (check-type string string)
      (incf count)
      (incf content-length (length string)))
    (let* ((total-length (+ content-length
                            (* separator-length (max 0 (1- count)))))
           (result (make-string total-length))
           (position 0)
           (firstp t))
      (dolist (string strings result)
        (unless firstp
          (replace result separator :start1 position)
          (incf position separator-length))
        (replace result string :start1 position)
        (incf position (length string))
        (setf firstp nil)))))

(defun %join-string-vector (strings separator separator-length)
  (declare (ignore separator-length))
  (with-output-to-string (out)
    (loop for string across strings
          for firstp = t then nil
          unless firstp
            do (write-string separator out)
          do (check-type string string)
             (write-string string out))))

(defun join-strings (strings &key (separator ""))
  "Join every string in the sequence STRINGS with SEPARATOR.

An empty sequence produces the empty string.  Each element must be a string;
values are never implicitly converted with PRINC."
  (check-type strings sequence)
  (check-type separator string)
  (let ((separator-length (length separator)))
    (etypecase strings
      (list (%join-string-list strings separator separator-length))
      (vector (%join-string-vector strings separator separator-length)))))
