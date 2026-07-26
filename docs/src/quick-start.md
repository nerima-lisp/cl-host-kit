# Quick Start

```lisp
(asdf:load-system "cl-host-kit")

;; Environment variables.
(host-kit:getenv "HOME")               ; => "/Users/ada"
(setf (host-kit:getenv "MY_VAR") "1")  ; set
(setf (host-kit:getenv "MY_VAR") nil)  ; unset

;; Working directory.
(host-kit:getcwd)                      ; => #P"/Users/ada/project/"
(host-kit:chdir "/tmp/")

;; Pathnames.
(host-kit:absolute-pathname-p "/foo")       ; => T
(host-kit:directory-pathname-p "/foo/bar")  ; => NIL
(host-kit:ensure-directory-pathname "/foo/bar")  ; => #P"/foo/bar/"
(host-kit:ensure-absolute-pathname "bar.txt" "/foo/")  ; => #P"/foo/bar.txt"

;; Filesystem.
(host-kit:file-exists-p "README.md")        ; => truename, or NIL
(host-kit:directory-exists-p "src/")        ; => truename, or NIL
(host-kit:directory-files "src/")           ; => list of file pathnames
(host-kit:subdirectories ".")               ; => list of directory pathnames
(host-kit:read-file-string "README.md")     ; => the whole file as a string
(host-kit:temporary-directory)              ; => #P"/tmp/"

;; Strings.
(host-kit:split-string "a,b,,c" :separator ",")  ; => ("a" "b" "" "c")
(host-kit:string-prefix-p "ab" "abc")             ; => T
```

## Handling failures

Every function that touches the OS wraps an underlying failure in
`host-operation-failed`, a subtype of the package's base condition
`host-kit-error`. Catch one clause to handle every failure this library can
signal:

```lisp
(handler-case
    (host-kit:chdir "/does/not/exist")
  (host-kit:host-operation-failed (condition)
    (format t "~A failed on ~A: ~A~%"
            (host-kit:host-operation-failed-operation condition)
            (host-kit:host-operation-failed-target condition)
            (host-kit:host-operation-failed-reason condition))))
```
