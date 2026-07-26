;;;; src/strings.lisp
;;;;
;;;; Two string helpers, scoped to exactly how the rest of nerima-lisp calls
;;;; them today (see the org-wide call-site survey in the design notes):
;;;; SPLIT-STRING never receives a :MAX argument anywhere in the org, and its
;;;; :SEPARATOR is always a bag of individual delimiter characters (a list of
;;;; characters, or a string treated as one), never a multi-character
;;;; delimiter sequence. STRING-PREFIX-P is the plain two-argument predicate.
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
