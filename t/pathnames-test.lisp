;;;; t/pathnames-test.lisp
(in-package #:cl-host-kit/test)

(describe "absolute-pathname-p"
  (it "is true for an absolute pathname"
    (expect (absolute-pathname-p "/foo/bar") :to-be-truthy))
  (it "is false for a relative pathname"
    (expect (absolute-pathname-p "foo/bar") :to-be-falsy)))

(describe "directory-pathname-p"
  (it "is true for a directory-form pathname"
    (expect (directory-pathname-p "/foo/bar/") :to-be-truthy))
  (it "is false for a pathname with a name and type"
    (expect (directory-pathname-p "/foo/bar.txt") :to-be-falsy)))

(describe "ensure-pathname"
  (it "coerces a string designator into a pathname"
    (expect (namestring (ensure-pathname "foo/bar.txt")) :to-equal "foo/bar.txt")))

(describe "ensure-directory-pathname"
  (it "leaves an already-directory-form pathname unchanged"
    (expect (namestring (ensure-directory-pathname "/foo/bar/")) :to-equal "/foo/bar/"))
  (it "folds a file's name and type into the directory"
    (expect (namestring (ensure-directory-pathname "/foo/bar.txt")) :to-equal "/foo/bar.txt/")))

(describe "ensure-absolute-pathname"
  (it "returns an already-absolute pathname unchanged"
    (expect (namestring (ensure-absolute-pathname "/foo/bar.txt")) :to-equal "/foo/bar.txt"))
  (it "merges a relative pathname against the given defaults"
    (expect (namestring (ensure-absolute-pathname "bar.txt" "/foo/")) :to-equal "/foo/bar.txt")))

(describe "pathname-directory-pathname"
  (it "strips the name and type, keeping only the directory"
    (expect (namestring (pathname-directory-pathname "/foo/bar.txt")) :to-equal "/foo/")))

(describe "truenamize"
  (it "returns the truename of an existing file, resolving symlinks"
    (let ((scratch (ensure-directories-exist
                     (merge-pathnames "cl-host-kit-truenamize-test/" (temporary-directory)))))
      (unwind-protect
           (let ((file (merge-pathnames "target.txt" scratch)))
             (with-open-file (stream file :direction :output :if-exists :supersede)
               (write-string "x" stream))
             (expect (namestring (truenamize file)) :to-equal (namestring (probe-file file))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "resolves the nearest existing parent when the file itself is missing"
    (let ((scratch (ensure-directories-exist
                     (merge-pathnames "cl-host-kit-truenamize-test/" (temporary-directory)))))
      (unwind-protect
           (let ((missing (merge-pathnames "missing.txt" scratch)))
             (expect (namestring (truenamize missing))
                     :to-equal (namestring (merge-pathnames "missing.txt" (probe-file scratch)))))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))
