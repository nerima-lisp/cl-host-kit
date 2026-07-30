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

(describe "parent-directory-pathname"
  (it "returns the containing directory for a file"
    (expect (namestring (parent-directory-pathname "/foo/bar.txt")) :to-equal "/"))

  (it "returns the parent of a directory-form pathname"
    (expect (namestring (parent-directory-pathname "/foo/bar/")) :to-equal "/foo/"))

  (it "keeps the filesystem root as its own parent"
    (expect (namestring (parent-directory-pathname "/")) :to-equal "/")))

(describe "truenamize"
  (it "returns the truename of an existing file, resolving symlinks"
    (let ((scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-truenamize-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (let ((file (merge-pathnames "target.txt" scratch)))
             (with-open-file (stream file :direction :output :if-exists :supersede)
               (write-string "x" stream))
             (expect (namestring (truenamize file)) :to-equal
                     (namestring (probe-file file))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "resolves the nearest existing parent when the file itself is missing"
    (let ((scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-truenamize-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (let ((missing (merge-pathnames "missing.txt" scratch)))
             (expect (namestring (truenamize missing))
                     :to-equal
                     (namestring (merge-pathnames "missing.txt"
                                                  (probe-file scratch)))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "resolves an existing ancestor before preserving nested missing components"
    (let ((scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-truenamize-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (let* ((actual-parent
                    (ensure-directories-exist
                     (merge-pathnames "actual/" scratch)))
                  (link (merge-pathnames "linked" scratch))
                  (missing (merge-pathnames "one/two/file.txt"
                                            (ensure-directory-pathname link))))
             (sb-posix:symlink (namestring actual-parent) (namestring link))
             (expect (namestring (truenamize missing))
                     :to-equal
                     (namestring (merge-pathnames "one/two/file.txt"
                                                  (probe-file actual-parent)))))
        (delete-directory-tree scratch :if-does-not-exist :ignore))))

  (it "normalizes parent components below a missing directory"
    (let ((scratch (ensure-directories-exist
                    (merge-pathnames "cl-host-kit-truenamize-test/"
                                     (temporary-directory)))))
      (unwind-protect
           (let ((pathspec (merge-pathnames "missing/../target.txt" scratch)))
             (expect (namestring (truenamize pathspec))
                     :to-equal
                     (namestring (merge-pathnames "target.txt"
                                                  (probe-file scratch)))))
        (delete-directory-tree scratch :if-does-not-exist :ignore)))))

(describe "pathname-within-p"
  (it "recognizes a pathname below its directory"
    (expect (pathname-within-p "/srv/app/cache/state.txt" "/srv/app/")
            :to-be-truthy))

  (it "rejects a sibling pathname and parent traversal outside the directory"
    (expect (pathname-within-p "/srv/other/state.txt" "/srv/app/")
            :to-be-falsy)
    (expect (pathname-within-p "/srv/app/cache/../../other/state.txt" "/srv/app/")
            :to-be-falsy))

  (it "resolves ancestor symbolic links only when requested"
    (call-with-temporary-directory
      (lambda (scratch)
        (let* ((root (merge-pathnames "root/" scratch))
               (outside (merge-pathnames "outside/" scratch))
               (alias (merge-pathnames "alias" root))
               (candidate (merge-pathnames "alias/missing.txt" root)))
          (ensure-directory-tree root)
          (ensure-directory-tree outside)
          (create-symbolic-link (namestring outside) alias)
          (expect (pathname-within-p candidate root) :to-be-truthy)
          (expect (pathname-within-p candidate root :resolve-symlinks t)
                  :to-be-falsy)))
      :prefix "cl-host-kit-pathname-within-")))

(describe "relative-pathname"
  (it "preserves a file name below the base directory"
    (expect (namestring (relative-pathname "/srv/app/cache/state.txt" "/srv/app/"))
            :to-equal "cache/state.txt"))

  (it "emits parent components before the target suffix"
    (expect (namestring (relative-pathname "/srv/release/app.txt" "/srv/build/tmp/"))
            :to-equal "../../release/app.txt"))

  (it "preserves a directory-form target pathname"
    (expect (namestring (relative-pathname "/srv/app/assets/" "/srv/app/cache/"))
            :to-equal "../assets/"))

  (it "absolutizes relative arguments before calculating the result"
    (let ((*default-pathname-defaults* #P"/srv/app/"))
      (expect (namestring (relative-pathname "logs/app.txt" "cache/"))
              :to-equal "../logs/app.txt"))))
