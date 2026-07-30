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

(describe "string-prefix-p"
  (it "is true when STRING starts with PREFIX"
    (expect (string-prefix-p "ab" "abc") :to-be-truthy))

  (it "is false when STRING does not start with PREFIX"
    (expect (string-prefix-p "xy" "abc") :to-be-falsy))

  (it "is false when PREFIX is longer than STRING"
    (expect (string-prefix-p "abcd" "abc") :to-be-falsy))

  (it "is true for an empty PREFIX"
    (expect (string-prefix-p "" "abc") :to-be-truthy)))
