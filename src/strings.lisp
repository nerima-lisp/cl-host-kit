;;;; src/strings.lisp
;;;;
;;;; Two string helpers, scoped to exactly how the rest of nerima-lisp calls
;;;; them today (see the org-wide call-site survey in the design notes):
;;;; SPLIT-STRING accepts :MAX because upstream UIOP does, and its :SEPARATOR is
;;;; always a bag of individual delimiter characters (a list of characters, or
;;;; a string treated as one), never a multi-character delimiter sequence.
;;;; STRING-PREFIX-P is the plain two-argument predicate.
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

(defun split-string (string &key (separator #\Space) max)
  "Split STRING wherever any character in SEPARATOR (a list of characters, a string of characters, or a single character) appears, treating each separator character as an independent one-character delimiter. Consecutive separator characters produce empty-string segments between them, matching the behavior response-file and line-oriented callers in this org rely on.

When MAX is supplied, split at most CEILING(MAX) - 1 times and keep the remaining substring as the final segment."
  (check-type string string)
  (let ((remaining-splits (and max (max 0 (1- (ceiling max))))))
    (flet ((scan-character (separator-character)
             (declare (type character separator-character))
             (%split-string-when
              (string separator-character character remaining-splits)
              (char= character separator-character)))
           (scan-character-set (separator-string)
             (declare (type string separator-string))
             (%split-string-when
              (string separator-string character remaining-splits)
              (find character separator-string))))
      (declare (inline scan-character scan-character-set))
      (etypecase separator
        (character (scan-character separator))
        (string
          (let ((separator-length (length separator)))
            (cond
              ((zerop separator-length) (list (copy-seq string)))
              ((= separator-length 1) (scan-character (char separator 0)))
              (t (scan-character-set separator)))))
        (list
          (cond
            ((endp separator) (list (copy-seq string)))
            ((endp (cdr separator))
              (let ((separator-character (car separator)))
                (check-type separator-character character)
                (scan-character separator-character)))
            (t
              (let ((separator-string (make-string (length separator))))
                (loop for separator-character in separator
                      for index fixnum from 0
                      do (check-type separator-character character) (setf (char separator-string index) separator-character))
                (scan-character-set separator-string)))))))))

(defun string-prefix-p (prefix string)
  "True when STRING starts with PREFIX."
  (declare (type string prefix string)
           (optimize (speed 3) (safety 1) (debug 0)))
  (let ((prefix-length (length prefix)))
    (and
      (<= prefix-length (length string))
      (string= prefix string :end2 prefix-length))))
