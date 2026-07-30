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

(describe "split-string with :max"
  (it "limits the number of resulting segments"
    (expect (split-string "a,b,c,d" :separator "," :max 2)
            :to-equal '("a" "b,c,d")))

  (it "treats fractional maxima like their ceiling"
    (expect (split-string "a,b,c,d" :separator "," :max 2.5)
            :to-equal '("a" "b" "c,d")))

  (it "does not split when MAX is at most 1"
    (expect (split-string "a,b,c" :separator "," :max 1)
            :to-equal '("a,b,c")))

  (it "preserves empty segments inside the capped remainder"
    (expect (split-string "a,,b,,c" :separator "," :max 3)
            :to-equal '("a" "" "b,,c"))))

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
            (string separator character nil)
            (char= character separator))))
      :to-be-truthy)))

(describe
  "string-prefix-p / string-suffix-p properties"
  (it-property
      "any PREFIX/SUFFIX concatenation has PREFIX as a prefix and SUFFIX as a suffix"
      ((prefix (gen-string :min-length 0 :max-length 12))
       (suffix (gen-string :min-length 0 :max-length 12)))
    (let ((joined (concatenate 'string prefix suffix)))
      (expect (string-prefix-p prefix joined) :to-be-truthy)
      (expect (string-suffix-p suffix joined) :to-be-truthy))))

(describe
  "split-string / join-strings round trip"
  (it-property
      "joining SPLIT-STRING's segments with the same separator reconstructs the original string"
      ((separator (gen-character :alphabet ",;: "))
       (content (gen-string :min-length 0 :max-length 40 :alphabet "abc,;: ")))
    (expect
      (join-strings (split-string content :separator separator) :separator (string separator))
      :to-equal
      content)))

(describe "string-suffix-p"
  (it "is true when STRING ends with SUFFIX"
    (expect (string-suffix-p "bc" "abc") :to-be-truthy))

  (it "is false when STRING does not end with SUFFIX"
    (expect (string-suffix-p "xy" "abc") :to-be-falsy))

  (it "is false when SUFFIX is longer than STRING"
    (expect (string-suffix-p "abcd" "abc") :to-be-falsy))

  (it "is true for an empty SUFFIX"
    (expect (string-suffix-p "" "abc") :to-be-truthy)))

(describe "join-strings"
  (it "joins a list with the requested separator"
    (expect (join-strings '("one" "two" "three") :separator "/")
            :to-equal "one/two/three"))

  (it "accepts arbitrary sequences of strings"
    (expect (join-strings #("one" "two") :separator ",")
            :to-equal "one,two"))

  (it "returns an empty string for an empty sequence"
    (expect (join-strings '() :separator ",") :to-equal ""))

  (it "rejects non-sequence inputs, non-string separators, and non-string elements"
  (signals type-error
    (join-strings 42))
  (signals type-error
    (join-strings '("valid") :separator 42))
  (signals type-error
    (join-strings '("valid" 42)))))
