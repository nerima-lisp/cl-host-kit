;;;; t/pathnames-test.lisp
(in-package #:cl-host-kit/test)

(describe
  "absolute-pathname-p"
  (it
    "is true for an absolute pathname"
    (expect (absolute-pathname-p "/foo/bar") :to-be-truthy))
  (it
    "is false for a relative pathname"
    (expect (absolute-pathname-p "foo/bar") :to-be-falsy)))

(describe
  "directory-pathname-p"
  (it
    "is true for a directory-form pathname"
    (expect (directory-pathname-p "/foo/bar/") :to-be-truthy))
  (it
    "is false for a pathname with a name and type"
    (expect (directory-pathname-p "/foo/bar.txt") :to-be-falsy))
  (it
    "is false for a pathname with only a type"
    (expect
      (directory-pathname-p (make-pathname :name nil :type "txt"))
      :to-be-falsy)))

(describe
  "ensure-pathname"
  (it
    "coerces a string designator into a pathname"
    (expect (namestring (ensure-pathname "foo/bar.txt")) :to-equal "foo/bar.txt")))

(describe
  "ensure-directory-pathname"
  (it
    "leaves an already-directory-form pathname unchanged"
    (expect
      (namestring (ensure-directory-pathname "/foo/bar/"))
      :to-equal
      "/foo/bar/"))
  (it
    "folds a filename and type into the directory"
    (expect
      (namestring (ensure-directory-pathname "/foo/bar.txt"))
      :to-equal
      "/foo/bar.txt/"))
  (it
    "makes a relative filename directory-form"
    (expect
      (namestring (ensure-directory-pathname "plain.txt"))
      :to-equal
      "plain.txt/")))

(describe
  "ensure-absolute-pathname"
  (it
    "returns an already-absolute pathname unchanged"
    (expect
      (namestring (ensure-absolute-pathname "/foo/bar.txt"))
      :to-equal
      "/foo/bar.txt"))
  (it
    "merges a relative pathname against the given defaults"
    (expect
      (namestring (ensure-absolute-pathname "bar.txt" "/foo/"))
      :to-equal
      "/foo/bar.txt")))

(describe
  "pathname-directory-pathname"
  (it
    "strips the name and type, keeping only the directory"
    (expect
      (namestring (pathname-directory-pathname "/foo/bar.txt"))
      :to-equal
      "/foo/")))

(describe
  "truenamize"
  (it
    "returns the target truename for a symbolic link"
    (let ((scratch
            (ensure-directories-exist
              (merge-pathnames "cl-host-kit-truenamize-test/" (temporary-directory)))))
      (unwind-protect
          (let ((target (merge-pathnames "target.txt" scratch))
                (link (merge-pathnames "link.txt" scratch)))
            (with-open-file (stream target :direction :output :if-exists :supersede)
              (write-string "x" stream))
            (sb-posix:symlink (namestring target) (namestring link))
            (expect
              (namestring (truenamize link))
              :to-equal
              (namestring (probe-file target))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))
  (it
    "resolves the nearest existing parent when the file itself is missing"
    (let ((scratch
            (ensure-directories-exist
              (merge-pathnames "cl-host-kit-truenamize-test/" (temporary-directory)))))
      (unwind-protect
          (let ((missing (merge-pathnames "missing.txt" scratch)))
            (expect
              (namestring (truenamize missing))
              :to-equal
              (namestring (merge-pathnames "missing.txt" (probe-file scratch)))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))
  (it
    "resolves the nearest existing ancestor of a deep missing path"
    (let ((scratch
            (ensure-directories-exist
              (merge-pathnames "cl-host-kit-truenamize-binary-search/" (temporary-directory)))))
      (unwind-protect
          (let ((missing
                  (merge-pathnames "missing-parent/missing-child/result.txt" scratch)))
            (expect
              (namestring (truenamize missing))
              :to-equal
              (namestring
                (merge-pathnames
                  "missing-parent/missing-child/result.txt"
                  (probe-file scratch)))))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))
