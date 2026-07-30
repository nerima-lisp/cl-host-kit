;;;; t/strings-test.lisp
(in-package #:cl-host-kit/test)

(describe
  "split-string"
  (it
    "splits on a list of separator characters"
    (expect
      (split-string "a b  c" :separator (quote (#\Space)))
      :to-equal
      (quote ("a" "b" "" "c"))))
  (it
    "splits on multiple list separator characters"
    (expect
      (split-string "a,b;c" :separator (quote (#\, #\;)))
      :to-equal
      (quote ("a" "b" "c"))))
  (it
    "treats an empty separator list as no delimiters"
    (expect (split-string "a,b,c" :separator nil) :to-equal (quote ("a,b,c"))))
  (it
    "accepts a separator string, treating each character as an independent delimiter"
    (expect (split-string "a,b;c" :separator ",;") :to-equal (quote ("a" "b" "c"))))
  (it
    "uses the character scan for a one-character separator string"
    (expect (split-string "a,b,c" :separator ",") :to-equal (quote ("a" "b" "c"))))
  (it
    "treats an empty separator string as no delimiters"
    (expect (split-string "a,b,c" :separator "") :to-equal (quote ("a,b,c"))))
  (it
    "accepts a single separator character"
    (expect (split-string "a:b:c" :separator #\:) :to-equal (quote ("a" "b" "c"))))
  (it
    "keeps empty segments between consecutive separators"
    (expect
      (split-string "a,,b" :separator (quote (#\,)))
      :to-equal
      (quote ("a" "" "b"))))
  (it
    "defaults to splitting on a single space"
    (expect (split-string "a b c") :to-equal (quote ("a" "b" "c"))))
  (it
    "returns the whole string as a single segment when no separator matches"
    (expect (split-string "abc" :separator (quote (#\,))) :to-equal (quote ("abc")))))

(describe
  "string-prefix-p"
  (it
    "is true when STRING starts with PREFIX"
    (expect (string-prefix-p "ab" "abc") :to-be-truthy))
  (it
    "is false when STRING does not start with PREFIX"
    (expect (string-prefix-p "xy" "abc") :to-be-falsy))
  (it
    "is false when PREFIX is longer than STRING"
    (expect (string-prefix-p "abcd" "abc") :to-be-falsy))
  (it
    "is true for an empty PREFIX"
    (expect (string-prefix-p "" "abc") :to-be-truthy)))

(describe
  "split-string edge cases"
  (it
    "returns one empty segment for an empty string"
    (expect (split-string "" :separator #\,) :to-equal (list "")))
  (it
    "keeps leading, trailing, and consecutive empty segments"
    (expect
      (split-string ",a,,b," :separator #\,)
      :to-equal
      (list "" "a" "" "b" "")))
  (it
    "signals TYPE-ERROR for an unsupported separator designator"
    (signals type-error (split-string "a,b" :separator 42)))
  (it
    "validates a single-element list separator before scanning"
    (signals type-error (split-string "x" :separator (quote (42)))))
  (it
    "validates every multi-character list separator before scanning"
    (signals type-error (split-string "a,b" :separator (quote (#\, 42))))))

(describe
  "split-string implementation"
  (it
    "expands the shared scanning macro"
    (expect
      (macroexpand-1
        (quote
          (host-kit::%split-string-when
            (string separator character)
            (char= character separator))))
      :to-be-truthy)))
