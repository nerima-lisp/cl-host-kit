;;;; t/directory-operations-test.lisp
(in-package #:cl-host-kit/test)

(describe
  "directory-empty-p regular entries"
  (it
    "returns false for a direct regular-file entry"
    (with-scratch-directory
      (scratch)
      (write-file-string "content" (merge-pathnames "entry.txt" scratch))
      (expect (directory-empty-p scratch) :to-be nil))))

(describe
  "directory-empty-p"
  (it
    "counts dotfiles and regular files as direct entries"
    (with-scratch-directory
      (scratch)
      (expect (directory-empty-p scratch) :to-be-truthy)
      (write-file-string "hidden" (merge-pathnames ".hidden" scratch))
      (expect (directory-empty-p scratch) :to-be nil)))
  (it
    "signals host-operation-failed for missing paths and regular files"
    (with-scratch-directory
      (scratch)
      (write-file-string "content" (merge-pathnames "file.txt" scratch))
      (signals
        host-operation-failed
        (directory-empty-p (merge-pathnames "file.txt" scratch)))
      (signals
        host-operation-failed
        (directory-empty-p (merge-pathnames "missing/" scratch))))))

(describe
  "directory-files / subdirectories"
  (it
    "directory-files list direct regular files including dotfiles in lexical order"
    (with-scratch-directory
      (scratch)
      (with-open-file (stream
          (merge-pathnames "a.txt" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (with-open-file (stream
          (merge-pathnames ".hidden" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (with-open-file (stream
          (merge-pathnames "noext" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (ensure-directories-exist (merge-pathnames "child/" scratch))
      (let ((names (mapcar #'file-namestring (directory-files scratch))))
        (expect names :to-equal (list ".hidden" "a.txt" "noext")))))
  (it
    "subdirectories list direct dot-directories in lexical order"
    (with-scratch-directory
      (scratch)
      (ensure-directories-exist (merge-pathnames ".hidden-directory/" scratch))
      (ensure-directories-exist (merge-pathnames "child-a/" scratch))
      (ensure-directories-exist (merge-pathnames "child-b/grandchild/" scratch))
      (let ((names
            (mapcar
              (lambda (pathname)
                (car (last (pathname-directory pathname))))
              (subdirectories scratch))))
        (expect names :to-equal (list ".hidden-directory" "child-a" "child-b")))))
  (it
    "optionally follows direct symbolic links while classifying entries"
    (with-scratch-directory
      (scratch)
      (let ((file-target (merge-pathnames "regular-target.txt" scratch))
            (file-link (merge-pathnames "regular-link.txt" scratch))
            (directory-target (merge-pathnames "directory-target/" scratch))
            (directory-link (merge-pathnames "directory-link" scratch)))
        (write-file-string "payload" file-target)
        (ensure-directory-tree directory-target)
        (create-symbolic-link file-target file-link)
        (create-symbolic-link directory-target directory-link)
        (expect
          (mapcar #'file-namestring (directory-files scratch))
          :to-equal
          (list "regular-target.txt"))
        (expect
          (mapcar #'file-namestring (directory-files scratch :follow-symlinks t))
          :to-equal
          (list "regular-link.txt" "regular-target.txt"))
        (expect
          (mapcar
            (lambda (pathname)
              (car (last (pathname-directory pathname))))
            (subdirectories scratch))
          :to-equal
          (list "directory-target"))
        (expect
          (mapcar
            (lambda (pathname)
              (car (last (pathname-directory pathname))))
            (subdirectories scratch :follow-symlinks t))
          :to-equal
          (list "directory-link" "directory-target"))
        (signals type-error (directory-files scratch :follow-symlinks :invalid))
        (signals type-error (subdirectories scratch :follow-symlinks :invalid))))))

(describe
  "call-with-directory-entries / with-directory-entries"
  (it
    "visits direct dotfiles and entries in lexical order without descending"
    (with-scratch-directory
      (scratch)
      (let ((root (merge-pathnames "entries/" scratch))
            (seen '()))
        (ensure-directory-tree (merge-pathnames "child/" root))
        (write-file-string "hidden" (merge-pathnames ".hidden" root))
        (write-file-string "leaf" (merge-pathnames "child/leaf.txt" root))
        (write-file-string "root" (merge-pathnames "root.txt" root))
        (with-directory-entries
          (pathname metadata root)
          (push (cons (file-namestring pathname) (file-metadata-kind metadata)) seen))
        (expect
          (nreverse seen)
          :to-equal
          '((".hidden" . :regular-file)
            ("child" . :directory)
            ("root.txt" . :regular-file))))))
  (it
    "honors the symbolic-link metadata policy"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target.txt" scratch))
            (link (merge-pathnames "target-link" scratch))
            (without-following '())
            (with-following '()))
        (write-file-string "payload" target)
        (sb-posix:symlink (namestring target) (namestring link))
        (call-with-directory-entries
          (lambda (pathname metadata)
            (push
              (cons (file-namestring pathname) (file-metadata-kind metadata))
              without-following))
          scratch)
        (call-with-directory-entries
          (lambda (pathname metadata)
            (push
              (cons (file-namestring pathname) (file-metadata-kind metadata))
              with-following))
          scratch
          :follow-symlinks
          t)
        (expect
          (assoc "target-link" without-following :test #'string=)
          :to-equal
          '("target-link" . :symbolic-link))
        (expect
          (assoc "target-link" with-following :test #'string=)
          :to-equal
          '("target-link" . :regular-file)))))
  (it
    "stops immediately and validates arguments before enumeration"
    (with-scratch-directory
      (scratch)
      (let ((calls 0))
        (write-file-string "a" (merge-pathnames "a.txt" scratch))
        (write-file-string "b" (merge-pathnames "b.txt" scratch))
        (call-with-directory-entries
          (lambda (pathname metadata)
            (declare (ignore pathname metadata))
            (incf calls)
            :stop)
          scratch)
        (expect calls :to-equal 1)
        (signals type-error (call-with-directory-entries nil scratch))
        (let ((file (merge-pathnames "not-a-directory.txt" scratch)))
          (write-file-string "data" file)
          (signals
            host-operation-failed
            (call-with-directory-entries
              (lambda (pathname metadata)
                (declare (ignore pathname metadata)))
              file)))
        (signals
          type-error
          (call-with-directory-entries
            (lambda (&rest arguments)
              (declare (ignore arguments)))
            scratch
            :follow-symlinks
            :invalid))))))

(it
  "rejects invalid callback bindings during macroexpansion"
  (signals
    error
    (macroexpand-1 '(with-directory-entries (42 metadata "ignored") nil)))
  (signals
    error
    (macroexpand-1 '(with-directory-entries (nil metadata "ignored") nil)))
  (signals
    error
    (macroexpand-1 '(with-directory-entries (pathname t "ignored") nil)))
  (signals
    error
    (macroexpand-1 '(with-directory-entries (pathname nil "ignored") nil))))

(describe
  "call-with-directory-tree / with-directory-tree"
  (it
    "walks dotfiles in lexical depth-first order and can prune a subtree"
    (with-scratch-directory
      (scratch)
      (let ((root (merge-pathnames "tree/" scratch))
            (seen '())
            (depths '()))
        (ensure-directory-tree (merge-pathnames "child/" root))
        (ensure-directory-tree (merge-pathnames "skipped/" root))
        (write-file-string "hidden" (merge-pathnames ".hidden" root))
        (write-file-string "leaf" (merge-pathnames "child/leaf.txt" root))
        (write-file-string "root" (merge-pathnames "root.txt" root))
        (write-file-string "skip" (merge-pathnames "skipped/ignored.txt" root))
        (flet ((entry-name (pathname)
                 (let ((file-name (file-namestring pathname)))
                (if (plusp (length file-name)) file-name
                  (car (last (pathname-directory pathname)))))))
          (with-directory-tree
            (pathname metadata depth root)
            (declare (ignore metadata))
            (let ((name (entry-name pathname)))
              (push name seen)
              (push depth depths)
              (when (string= name "skipped")
                :skip-subtree)))
          (expect
            (nreverse seen)
            :to-equal
            '(".hidden" "child" "leaf.txt" "root.txt" "skipped"))
          (expect (nreverse depths) :to-equal '(1 1 2 1 1))))))
  (it
    "does not follow links by default and terminates link cycles when enabled"
    (with-scratch-directory
      (scratch)
      (let ((root (merge-pathnames "tree/" scratch))
            (link (merge-pathnames "tree/loop" scratch))
            (without-following '())
            (with-following '()))
        (ensure-directory-tree (merge-pathnames "child/" root))
        (write-file-string "leaf" (merge-pathnames "child/leaf.txt" root))
        (sb-posix:symlink "." (namestring link))
        (call-with-directory-tree
          (lambda (pathname metadata depth)
            (declare (ignore depth))
            (push
              (cons (file-namestring pathname) (file-metadata-kind metadata))
              without-following))
          root)
        (call-with-directory-tree
          (lambda (pathname metadata depth)
            (declare (ignore depth))
            (push
              (cons (file-namestring pathname) (file-metadata-kind metadata))
              with-following))
          root
          :follow-symlinks
          t)
        (expect
          (assoc "loop" without-following :test #'string=)
          :to-equal
          '("loop" . :symbolic-link))
        (expect
          (assoc "loop" with-following :test #'string=)
          :to-equal
          '("loop" . :directory))
        (expect (length with-following) :to-equal 3))))
  (it
    "stops before visiting later entries"
    (with-scratch-directory
      (scratch)
      (let ((root (merge-pathnames "tree/" scratch))
            (calls 0))
        (ensure-directory-tree root)
        (write-file-string "a" (merge-pathnames "a.txt" root))
        (write-file-string "b" (merge-pathnames "b.txt" root))
        (call-with-directory-tree
          (lambda (pathname metadata depth)
            (declare (ignore pathname metadata depth))
            (incf calls)
            :stop)
          root)
        (expect calls :to-equal 1))))
  (it
    "limits entries to the requested depth"
    (with-scratch-directory
      (scratch)
      (let ((root (merge-pathnames "tree/" scratch))
            (seen '()))
        (ensure-directory-tree (merge-pathnames "child/grandchild/" root))
        (write-file-string "root" (merge-pathnames "root.txt" root))
        (write-file-string "child" (merge-pathnames "child/leaf.txt" root))
        (write-file-string
          "grandchild"
          (merge-pathnames "child/grandchild/deep.txt" root))
        (with-directory-tree
          (pathname metadata depth root :max-depth 2)
          (declare (ignore metadata depth))
          (push (enough-namestring pathname root) seen))
        (expect
          (nreverse seen)
          :to-equal
          '("child" "child/grandchild" "child/leaf.txt" "root.txt"))
        (setf seen '())
        (call-with-directory-tree
          (lambda (pathname metadata depth)
            (declare (ignore pathname metadata depth))
            (push :unexpected seen))
          root
          :max-depth
          0)
        (expect seen :to-be nil))))
  (it
    "rejects a non-directory root before invoking the callback"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "not-a-directory.txt" scratch)))
        (write-file-string "data" file)
        (signals
          host-operation-failed
          (call-with-directory-tree
            (lambda (&rest arguments)
              (declare (ignore arguments)))
            file))))))

(it
  "rejects invalid callback bindings during macroexpansion"
  (signals
    error
    (macroexpand-1 '(with-directory-tree (42 metadata depth "ignored") nil)))
  (signals
    error
    (macroexpand-1 '(with-directory-tree (nil metadata depth "ignored") nil)))
  (signals
    error
    (macroexpand-1 '(with-directory-tree (pathname t depth "ignored") nil)))
  (signals
    error
    (macroexpand-1 '(with-directory-tree (pathname metadata t "ignored") nil))))

(it
  "validates the callback and symbolic-link policy before walking"
  (with-scratch-directory
    (scratch)
    (signals type-error (call-with-directory-tree nil scratch))
    (signals
      type-error
      (call-with-directory-tree
        (lambda (&rest arguments)
          (declare (ignore arguments)))
        scratch
        :follow-symlinks
        :invalid))
    (signals
      type-error
      (call-with-directory-tree
        (lambda (&rest arguments)
          (declare (ignore arguments)))
        scratch
        :max-depth
        -1))))

(describe
  "ensure-directory-tree"
  (it
    "creates missing nested directories and returns their canonical pathname"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "one/two/" scratch)))
        (expect (ensure-directory-tree target) :to-equal (truename target))
        (expect (directory-exists-p target) :to-equal (truename target))
        (expect (ensure-directory-tree target) :to-equal (truename target)))))
  (it
    "rejects an existing regular file at the requested directory location"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "not-a-directory" scratch)))
        (write-file-string "data" target)
        (signals host-operation-failed (ensure-directory-tree target)))))
  (it
    "wraps failures that occur while creating an invalid directory tree"
    (signals host-operation-failed (ensure-directory-tree "/dev/null/child/"))))

(progn
  (describe
    "delete-file-if-exists / delete-empty-directory"
    (it
      "deletes an existing regular file and reports whether it was present"
      (with-scratch-directory
        (scratch)
        (let ((file (merge-pathnames "remove.txt" scratch)))
          (write-file-string "data" file)
          (expect (delete-file-if-exists file) :to-be-truthy)
          (expect (file-exists-p file) :to-be nil)
          (expect (delete-file-if-exists file) :to-be nil))))
    (it
      "does not remove a directory through delete-file-if-exists"
      (with-scratch-directory
        (scratch)
        (expect (delete-file-if-exists scratch) :to-be nil)
        (expect (directory-exists-p scratch) :to-be-truthy)))
    (it
      "removes live and dangling symbolic links without deleting live targets"
      (with-scratch-directory
        (scratch)
        (let ((target (merge-pathnames "target.txt" scratch))
              (link (merge-pathnames "link.txt" scratch))
              (dangling-link (merge-pathnames "missing-link.txt" scratch)))
          (write-file-string "content" target)
          (sb-posix:symlink (namestring target) (namestring link))
          (sb-posix:symlink "missing.txt" (namestring dangling-link))
          (expect (delete-file-if-exists link) :to-be-truthy)
          (expect (path-exists-p link) :to-be nil)
          (expect (read-file-string target) :to-equal "content")
          (expect (delete-file-if-exists dangling-link) :to-be-truthy)
          (expect (path-exists-p dangling-link) :to-be nil))))
    (it
      "deletes an empty directory but rejects a non-empty one"
      (with-scratch-directory
        (scratch)
        (let ((empty (merge-pathnames "empty/" scratch))
              (non-empty (merge-pathnames "non-empty/" scratch)))
          (ensure-directory-tree empty)
          (delete-empty-directory empty)
          (expect (directory-exists-p empty) :to-be nil)
          (ensure-directory-tree non-empty)
          (write-file-string "data" (merge-pathnames "entry.txt" non-empty))
          (signals host-operation-failed (delete-empty-directory non-empty))))))
  (describe
    "delete-path"
    (it
      "removes a file and applies the missing-path policy"
      (with-scratch-directory
        (scratch)
        (let ((file (merge-pathnames "remove.txt" scratch))
              (missing (merge-pathnames "missing.txt" scratch)))
          (write-file-string "data" file)
          (expect (delete-path file) :to-be-truthy)
          (expect (path-exists-p file) :to-be nil)
          (expect (delete-path missing :if-does-not-exist :ignore) :to-be nil)
          (signals host-operation-failed (delete-path missing)))))
    (it
      "treats a path below a regular file as absent only when requested"
      (with-scratch-directory
        (scratch)
        (let ((file (merge-pathnames "not-a-directory" scratch))
              (child (merge-pathnames "not-a-directory/child" scratch)))
          (write-file-string "data" file)
          (expect (delete-path child :if-does-not-exist :ignore) :to-be nil)
          (expect (read-file-string file) :to-equal "data")
          (signals host-operation-failed (delete-path child)))))
    (it
      "requires recursion for a non-empty directory"
      (with-scratch-directory
        (scratch)
        (let ((empty (merge-pathnames "empty/" scratch))
              (tree (merge-pathnames "tree/" scratch)))
          (ensure-directory-tree empty)
          (expect (delete-path empty) :to-be-truthy)
          (expect (path-exists-p empty) :to-be nil)
          (ensure-directory-tree tree)
          (write-file-string "data" (merge-pathnames "entry.txt" tree))
          (signals host-operation-failed (delete-path tree))
          (expect (read-file-string (merge-pathnames "entry.txt" tree)) :to-equal "data")
          (expect (delete-path tree :recursive t) :to-be-truthy)
          (expect (path-exists-p tree) :to-be nil))))
    #+sbcl
  (it "unlinks directory and dangling symbolic links without touching targets"
    (with-scratch-directory
      (scratch)
      (let ((target (merge-pathnames "target/" scratch))
            (link (merge-pathnames "directory-link" scratch))
            (dangling (merge-pathnames "dangling-link" scratch))
            (missing-target (merge-pathnames "missing-target" scratch)))
        (ensure-directory-tree target)
        (write-file-string "preserve" (merge-pathnames "marker.txt" target))
        (sb-posix:symlink (namestring target) (namestring link))
        (expect (delete-path (ensure-directory-pathname link) :recursive t)
                :to-be-truthy)
        (expect (path-exists-p link) :to-be nil)
        (expect (read-file-string (merge-pathnames "marker.txt" target))
                :to-equal "preserve")
        (sb-posix:symlink (namestring missing-target) (namestring dangling))
        (expect (delete-path dangling) :to-be-truthy)
        (expect (path-exists-p dangling) :to-be nil))))
    (it
      "rejects invalid deletion options before touching the path"
      (with-scratch-directory
        (scratch)
        (signals type-error (delete-path scratch :recursive :invalid))
        (signals type-error (delete-path scratch :if-does-not-exist :invalid))
        (expect (directory-exists-p scratch) :to-be-truthy)))))

(describe
  "delete-directory-tree"
  (it
    "recursively deletes a non-empty directory"
    (with-scratch-directory
      (scratch)
      (ensure-directories-exist (merge-pathnames "child/" scratch))
      (with-open-file (stream
          (merge-pathnames "child/a.txt" scratch)
          :direction
          :output
          :if-exists
          :supersede)
        (write-string "x" stream))
      (delete-directory-tree scratch)
      (expect (directory-exists-p scratch) :to-be nil)))
  (it
    "signals by default when the directory does not exist"
    (signals
      host-operation-failed
      (delete-directory-tree "/definitely/does/not/exist/cl-host-kit-xyz")))
  (it
    "IF-DOES-NOT-EXIST :IGNORE silently succeeds when the directory is already gone"
    (expect
      (delete-directory-tree
        "/definitely/does/not/exist/cl-host-kit-xyz"
        :if-does-not-exist
        :ignore)
      :to-be
      nil))
  (it
    "does not suppress deletion failures for an existing non-directory"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "not-a-directory.txt" scratch)))
        (write-file-string "must remain" file)
        (signals
          host-operation-failed
          (delete-directory-tree file :if-does-not-exist :ignore))
        (expect (file-exists-p file) :to-be-truthy))))
  #+sbcl
  (it "rejects a directory link without traversing its target"
    (with-scratch-directory (scratch)
      (let ((target (merge-pathnames "protected/" scratch))
            (link (merge-pathnames "directory-link" scratch)))
        (ensure-directory-tree target)
        (write-file-string "must remain" (merge-pathnames "marker.txt" target))
        (sb-posix:symlink (namestring target) (namestring link))
        (signals host-operation-failed
          (delete-directory-tree (ensure-directory-pathname link)))
        (expect (symbolic-link-p link) :to-be-truthy)
        (expect (read-file-string (merge-pathnames "marker.txt" target))
                :to-equal "must remain"))))
  (it
    "validates deletion options before modifying the directory"
    (with-scratch-directory
      (scratch)
      (signals type-error (delete-directory-tree scratch :validate :invalid))
      (signals type-error (delete-directory-tree scratch :if-does-not-exist :invalid))
      (expect (directory-exists-p scratch) :to-be-truthy)))
  (it
    "VALIDATE T rejects a pathname that is not directory-form"
    (with-scratch-directory
      (scratch)
      (let ((file (merge-pathnames "not-a-directory.txt" scratch)))
        (with-open-file (stream file :direction :output :if-exists :supersede)
          (write-string "must remain" stream))
        (signals host-operation-failed (delete-directory-tree file :validate t))
        (expect (file-exists-p file) :to-be-truthy)))))

(describe
  "move-path"
  (it
    "moves a file to an absent target and returns its absolute pathname"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target.txt" scratch)))
        (with-open-file (stream source :direction :output :if-exists :supersede)
          (write-string "new" stream))
        (expect (move-path source target) :to-equal (ensure-absolute-pathname target))
        (expect (file-exists-p source) :to-be nil)
        (expect (read-file-string target) :to-equal "new"))))
  (it
    "moves a real directory without copying its contents"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source/" scratch))
            (target (merge-pathnames "target/" scratch)))
        (ensure-directory-tree source)
        (write-file-string "payload" (merge-pathnames "marker.txt" source))
        (expect (move-path source target) :to-equal (ensure-absolute-pathname target))
        (expect (path-exists-p source) :to-be nil)
        (expect
          (read-file-string (merge-pathnames "marker.txt" target))
          :to-equal
          "payload"))))
  (it
    "rejects an existing target by default without modifying either entry"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target.txt" scratch)))
        (write-file-string "new" source)
        (with-open-file (stream target :direction :output :if-exists :supersede)
          (write-string "old" stream))
        (signals host-operation-failed (move-path source target))
        (expect (read-file-string source) :to-equal "new")
        (expect (read-file-string target) :to-equal "old"))))
  (it
    "replaces an existing target only with explicit supersede"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target.txt" scratch)))
        (write-file-string "new" source)
        (write-file-string "old" target)
        (move-path source target :if-exists :supersede)
        (expect (file-exists-p source) :to-be nil)
        (expect (read-file-string target) :to-equal "new"))))
  (it
    "moves a dangling symbolic link without resolving it"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source-link" scratch))
            (target (merge-pathnames "target-link" scratch)))
        (create-symbolic-link "missing.txt" source)
        (move-path source target)
        (expect (path-exists-p source) :to-be nil)
        (expect (symbolic-link-p target) :to-be-truthy)
        (expect (read-symbolic-link target) :to-equal "missing.txt"))))
  #+sbcl
  (progn
    (it
      "falls back to a staged copy after EXDEV and replaces an explicit target"
      (with-scratch-directory
        (scratch)
        (let ((source (merge-pathnames "source.txt" scratch))
              (target (merge-pathnames "target.txt" scratch))
              (first-call-p t)
              (original
                (symbol-function
                 (quote host-kit::%rename-path-overwriting-target))))
          (write-file-string "source" source)
          (write-file-string "target" target)
          (with-function-redefinition
            ((quote host-kit::%rename-path-overwriting-target)
             (lambda (staged-source staged-target)
               (if first-call-p
                   (progn
                     (setf first-call-p nil)
                     (error (quote sb-posix:syscall-error) :errno sb-posix:exdev))
                   (funcall original staged-source staged-target))))
            (move-path source target :if-exists :supersede))
          (expect (path-exists-p source) :to-be nil)
          (expect (read-file-string target) :to-equal "source"))))
    (it
      "falls back to a staged copy for a directory after EXDEV"
      (with-scratch-directory
        (scratch)
        (let ((source (merge-pathnames "source/" scratch))
              (target (merge-pathnames "target/" scratch))
              (first-call-p t)
              (original
                (symbol-function
                 (quote host-kit::%rename-path-overwriting-target))))
          (ensure-directories-exist (merge-pathnames "nested/file.txt" source))
          (write-file-string "contents" (merge-pathnames "nested/file.txt" source))
          (with-function-redefinition
            ((quote host-kit::%rename-path-overwriting-target)
             (lambda (staged-source staged-target)
               (if first-call-p
                   (progn
                     (setf first-call-p nil)
                     (error (quote sb-posix:syscall-error) :errno sb-posix:exdev))
                   (funcall original staged-source staged-target))))
            (move-path source target))
          (expect (path-exists-p source) :to-be nil)
          (expect (read-file-string (merge-pathnames "nested/file.txt" target))
                  :to-equal
                  "contents"))))
    (it
      "falls back to a staged copy for a dangling symbolic link after EXDEV"
      (with-scratch-directory
        (scratch)
        (let ((source (merge-pathnames "source-link" scratch))
              (target (merge-pathnames "target-link" scratch))
              (first-call-p t)
              (original
                (symbol-function
                 (quote host-kit::%rename-path-overwriting-target))))
          (create-symbolic-link "missing-relative-target" source)
          (with-function-redefinition
            ((quote host-kit::%rename-path-overwriting-target)
             (lambda (staged-source staged-target)
               (if first-call-p
                   (progn
                     (setf first-call-p nil)
                     (error (quote sb-posix:syscall-error) :errno sb-posix:exdev))
                   (funcall original staged-source staged-target))))
            (move-path source target))
          (expect (path-exists-p source) :to-be nil)
          (expect (symbolic-link-p target) :to-be-truthy)
          (expect (read-symbolic-link target)
                  :to-equal
                  "missing-relative-target")))))
  (it
    "validates IF-EXISTS before modifying the source"
    (with-scratch-directory
      (scratch)
      (let ((source (merge-pathnames "source.txt" scratch))
            (target (merge-pathnames "target.txt" scratch)))
        (write-file-string "new" source)
        (signals type-error (move-path source target :if-exists :invalid))
        (expect (read-file-string source) :to-equal "new")
        (expect (path-exists-p target) :to-be nil))))
  (it
    "wraps a missing source failure in host-operation-failed"
    (with-scratch-directory
      (scratch)
      (signals
        host-operation-failed
        (move-path
          (merge-pathnames "missing.txt" scratch)
          (merge-pathnames "target.txt" scratch))))))

(when (member :sbcl *features*)
  (describe
    "create-directory"
    (it
      "creates one directory and returns its canonical pathname"
      (with-scratch-directory
        (scratch)
        (let ((target (merge-pathnames "child/" scratch)))
          (expect (create-directory target :mode #o700) :to-equal (truename target))
          (expect (directory-exists-p target) :to-equal (truename target)))))
    (it
      "does not create missing parent directories"
      (with-scratch-directory
        (scratch)
        (let ((target (merge-pathnames "missing/child/" scratch)))
          (signals host-operation-failed (create-directory target))
          (expect (directory-exists-p target) :to-be nil))))
    (it
      "requires an explicit policy for an existing directory"
      (with-scratch-directory
        (scratch)
        (let ((target (merge-pathnames "child/" scratch)))
          (create-directory target)
          (signals host-operation-failed (create-directory target))
          (expect
            (create-directory target :if-exists :ignore)
            :to-equal
            (truename target)))))
    (it
      "does not ignore an existing regular file"
      (with-scratch-directory
        (scratch)
        (let ((target (merge-pathnames "entry" scratch)))
          (write-file-string "content" target)
          (signals host-operation-failed (create-directory target :if-exists :ignore)))))
    (it
      "validates options before making filesystem changes"
      (with-scratch-directory
        (scratch)
        (let ((target (merge-pathnames "child/" scratch)))
          (signals type-error (create-directory target :mode -1))
          (signals type-error (create-directory target :if-exists :replace))
          (expect (directory-exists-p target) :to-be nil))))))

(describe
  "recursive root deletion protection"
  (it
    "rejects the filesystem root and resolved aliases"
    (dolist (pathspec (quote ("/" "/tmp/..")))
      (signals host-operation-failed (delete-directory-tree pathspec))
      (signals host-operation-failed (delete-path pathspec :recursive t)))))
