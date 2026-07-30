;;;; src/strings.lisp
;;;;
;;;; Two string helpers with a deliberately narrow contract: SPLIT-STRING
;;;; accepts a separator character or a bag of delimiter characters (a list
;;;; of characters, or a string treated as one), not a multi-character
;;;; delimiter sequence or a :MAX argument. STRING-PREFIX-P is the plain
;;;; two-argument predicate.
(in-package #:host-kit)

(defmacro %split-string-when ((string separator character) delimiter-p)
  "Expand the shared scan used by SPLIT-STRING separator specializations."
  (let ((segments (gensym "SEGMENTS"))
        (start (gensym "START"))
        (index (gensym "INDEX")))
    `(let ((,string ,string)
          (,separator ,separator)
          (,segments nil)
          (,start 0))
      (declare (type string ,string)
               (type fixnum ,start)
               (optimize (speed 3) (safety 1) (debug 0)))
      (loop for ,index fixnum from 0 below (length ,string)
            for ,character = (char ,string ,index)
            when ,delimiter-p
              do (push (subseq ,string ,start ,index) ,segments) (setf ,start (1+ ,index)))
      (push (subseq ,string ,start) ,segments)
      (nreverse ,segments))))

(defun split-string (string &key (separator #\Space))
  "Split STRING wherever any character in SEPARATOR (a list of characters, a string of characters, or a single character) appears, treating each separator character as an independent one-character delimiter. Consecutive separator characters produce empty-string segments between them, matching the behavior response-file and line-oriented callers in this org rely on."
  (check-type string string)
  (flet ((scan-character (separator-character)
           (declare (type character separator-character))
           (%split-string-when
          (string separator-character character)
          (char= character separator-character)))
         (scan-character-set (separator-string)
           (declare (type string separator-string))
           (%split-string-when
          (string separator-string character)
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
              (scan-character-set separator-string))))))))

(defun string-prefix-p (prefix string)
  "True when STRING starts with PREFIX."
  (declare (type string prefix string)
           (optimize (speed 3) (safety 1) (debug 0)))
  (let ((prefix-length (length prefix)))
    (and
      (<= prefix-length (length string))
      (string= prefix string :end2 prefix-length))))
