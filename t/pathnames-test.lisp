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

(describe "parent-directory-pathname"
  (it "returns the containing directory for a file"
    (expect (namestring (parent-directory-pathname "/foo/bar.txt")) :to-equal "/"))

  (it "returns the parent of a directory-form pathname"
    (expect (namestring (parent-directory-pathname "/foo/bar/")) :to-equal "/foo/"))

  (it "keeps the filesystem root as its own parent"
    (expect (namestring (parent-directory-pathname "/")) :to-equal "/")))

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

(describe
 "pathname-within-p"
 (it
  "accepts the directory itself and a child pathname"
  (expect (pathname-within-p "/srv/app/" "/srv/app/") :to-be-truthy)
  (expect
   (pathname-within-p "/srv/app/cache/state.txt" "/srv/app/")
   :to-be-truthy))
 (it
  "handles deep descendants and directories longer than the candidate"
  (expect
   (pathname-within-p
    "/srv/app/one/two/three/four/five/six/seven/eight/state.txt"
    "/srv/app/")
   :to-be-truthy)
  (expect (pathname-within-p "/srv/app/" "/srv/app/cache/deep/") :to-be-falsy))
 (it
  "rejects sibling and component-boundary pathnames"
  (expect (pathname-within-p "/srv/other/state.txt" "/srv/app/") :to-be-falsy)
  (expect
   (pathname-within-p "/srv/application/state.txt" "/srv/app/")
   :to-be-falsy))
 (it
  "rejects parent traversal outside the directory"
  (expect
   (pathname-within-p "/srv/app/cache/../../other/state.txt" "/srv/app/")
   :to-be-falsy))
 (it
  "absolutizes relative arguments once before lexical normalization"
  (let ((*default-pathname-defaults* #P"/srv/work/"))
    (expect (pathname-within-p "app/cache/state.txt" "app/") :to-be-truthy)
    (expect (pathname-within-p "outside/state.txt" "app/") :to-be-falsy)))
 (it
  "resolves ancestor symbolic links only when requested"
  (with-scratch-directory (scratch)
     (let* ((root (merge-pathnames "root/" scratch))
            (outside (merge-pathnames "outside/" scratch))
            (alias (merge-pathnames "alias" root))
            (candidate (merge-pathnames "alias/missing.txt" root)))
       (ensure-directory-tree root)
       (ensure-directory-tree outside)
       (create-symbolic-link (namestring outside) alias)
       (expect (pathname-within-p candidate root) :to-be-truthy)
       (expect (pathname-within-p candidate root :resolve-symlinks t) :to-be-falsy)))))

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

(describe "native directory-form pathname components"
  (it "folds a physical literal file part into a directory without adding escapes"
    (let* ((input (sb-ext:parse-native-namestring "/tmp/literal*?[x]\\back.txt"))
           (actual (ensure-directory-pathname input)))
      (expect actual
              :to-equal (sb-ext:parse-native-namestring "/tmp/literal*?[x]\\back.txt/"))
      (expect (car (last (pathname-directory actual)))
              :to-equal "literal*?[x]\\back.txt")
      (expect (wild-pathname-p actual) :to-be nil)))
  (it-each ((#P"/tmp/.hidden" (:absolute "tmp" ".hidden"))
            (#P"/tmp/name." (:absolute "tmp" "name."))
            (#P"/tmp/*.txt" (:absolute "tmp" "*.txt"))
            (#P"/tmp/name.*" (:absolute "tmp" "name.*"))
            (#P"/tmp/*/name.txt" (:absolute "tmp" :wild "name.txt"))
            (#P"/tmp/*/" (:absolute "tmp" :wild)))
      "preserves the lexical directory components of ~S" (input components)
    (let ((actual (ensure-directory-pathname input)))
      (expect (pathname-directory actual) :to-equal components)
      (expect (directory-pathname-p actual) :to-be t)))
  (it "preserves an explicit physical pathname version"
    (let* ((input (make-pathname :directory '(:absolute "tmp")
                                 :name "name" :type "txt" :version 42))
           (actual (ensure-directory-pathname input)))
      (expect (pathname-directory actual) :to-equal '(:absolute "tmp" "name.txt"))
      (expect (pathname-version actual) :to-equal 42)))
  (it "preserves the error for a type-only physical pathname"
    (signals sb-kernel::no-namestring-error
      (ensure-directory-pathname
       (make-pathname :directory '(:absolute "tmp") :name nil :type "txt"))))
  (it "preserves the error for the existing logical pathname form"
    (signals sb-kernel::namestring-parse-error
      (ensure-directory-pathname (logical-pathname "SYS:FOO;BAR.LISP.NEWEST")))))

(cl-weave:describe-sequential "native OS pathname logical translation"
  (it "converts a logical pathname to the native name of its physical file"
    (with-scratch-directory (scratch)
      (let* ((host (symbol-name (gensym "HOST-KIT-NATIVE-TEST-")))
             (previous nil)
             (physical (merge-pathnames "entry.txt" scratch)))
        (write-file-string "payload" physical)
        (unwind-protect
             (progn
               (setf (logical-pathname-translations host)
                     (list (list "**;*.*.*" (merge-pathnames "**/*.*" scratch))))
               (let ((native (host-kit::%native-file-namestring
                              (logical-pathname (format nil "~A:ENTRY.TXT" host)))))
                 (expect native :to-equal (sb-ext:native-namestring physical))
                 (expect (read-file-string native) :to-equal "payload")
                 (expect (same-file-p native physical) :to-be t)))
          (setf (logical-pathname-translations host) previous))))))
