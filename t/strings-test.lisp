;;;; t/strings-test.lisp
(in-package #:cl-host-kit/test)

(describe "split-string"
  (it "splits on a list of separator characters"
    (expect (split-string "a b  c" :separator '(#\Space)) :to-equal '("a" "b" "" "c")))

  (it "accepts a separator string, treating each character as an independent delimiter"
    (expect (split-string "a,b;c" :separator ",;") :to-equal '("a" "b" "c")))

  (it "accepts a single separator character"
    (expect (split-string "a:b:c" :separator #\:) :to-equal '("a" "b" "c")))

  (it "keeps empty segments between consecutive separators"
    (expect (split-string "a,,b" :separator '(#\,)) :to-equal '("a" "" "b")))

  (it "defaults to splitting on a single space"
    (expect (split-string "a b c") :to-equal '("a" "b" "c")))

  (it "returns the whole string as a single segment when no separator matches"
    (expect (split-string "abc" :separator '(#\,)) :to-equal '("abc"))))

(describe "string-prefix-p"
  (it "is true when STRING starts with PREFIX"
    (expect (string-prefix-p "ab" "abc") :to-be-truthy))

  (it "is false when STRING does not start with PREFIX"
    (expect (string-prefix-p "xy" "abc") :to-be-falsy))

  (it "is false when PREFIX is longer than STRING"
    (expect (string-prefix-p "abcd" "abc") :to-be-falsy))

  (it "is true for an empty PREFIX"
    (expect (string-prefix-p "" "abc") :to-be-truthy)))

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
