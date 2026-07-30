;;;; src/strings.lisp
;;;;
;;;; Small, dependency-free string primitives.  Delimiters remain explicit:
;;;; SPLIT-STRING treats its separator as a bag of independent characters,
;;;; never as a multi-character delimiter sequence.
(in-package #:host-kit)

(defun %separator-characters (separator)
  (etypecase separator
    (list separator)
    (string (coerce separator 'list))
    (character (list separator))))

(defun split-string (string &key (separator '(#\Space)))
  "Split STRING wherever any character in SEPARATOR (a list of characters, a
string of characters, or a single character) appears, treating each
separator character as an independent one-character delimiter. Consecutive
separator characters produce empty-string segments between them, matching
the behavior response-file and line-oriented callers in this org rely on."
  (let ((separator-characters (%separator-characters separator))
        (segments nil)
        (start 0))
    (loop for index from 0 below (length string)
          when (member (char string index) separator-characters :test #'char=)
            do (push (subseq string start index) segments)
               (setf start (1+ index)))
    (push (subseq string start) segments)
    (nreverse segments)))

(defun string-prefix-p (prefix string)
  "True when STRING starts with PREFIX."
  (let ((prefix-length (length prefix)))
    (and (<= prefix-length (length string))
         (string= prefix string :end2 prefix-length))))

(defun string-suffix-p (suffix string)
  "True when STRING ends with SUFFIX."
  (let ((suffix-length (length suffix))
        (string-length (length string)))
    (and (<= suffix-length string-length)
         (string= suffix string :start2 (- string-length suffix-length)))))

(defun join-strings (strings &key (separator ""))
  "Join every string in the sequence STRINGS with SEPARATOR.

An empty sequence produces the empty string.  Each element must be a string;
values are never implicitly converted with PRINC."
  (check-type strings sequence)
  (check-type separator string)
  (with-output-to-string (output)
    (loop with firstp = t
          for string across (coerce strings 'vector)
          do (unless firstp
               (write-string separator output))
             (check-type string string)
             (write-string string output)
             (setf firstp nil))))
