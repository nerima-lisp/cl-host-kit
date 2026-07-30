# Quick Start

```lisp
(asdf:load-system "cl-host-kit")

;; Environment variables.
(host-kit:getenv "HOME")               ; => "/Users/ada"
(setf (host-kit:getenv "MY_VAR") "1")  ; set
(setf (host-kit:getenv "MY_VAR") nil)  ; unset
(host-kit:with-environment-variable ("MY_VAR" "temporary")
  (host-kit:getenv "MY_VAR"))          ; restored after the body exits
(host-kit:command-line-arguments)      ; => ("--serve" "8080")
(host-kit:hostname)                     ; => "build-host"
(host-kit:user-config-directory)        ; => #P"/Users/ada/.config/"
(host-kit:user-data-directory)          ; => #P"/Users/ada/.local/share/"
(host-kit:user-runtime-directory)       ; => #P"/run/user/501/" or NIL

;; Working directory.
(host-kit:getcwd)                      ; => #P"/Users/ada/project/"
(host-kit:chdir "/tmp/")
(host-kit:with-working-directory ("/tmp/")
  (host-kit:directory-files "."))      ; restored after the body exits

;; Pathnames.
(host-kit:absolute-pathname-p "/foo")       ; => T
(host-kit:directory-pathname-p "/foo/bar")  ; => NIL
(host-kit:ensure-directory-pathname "/foo/bar")  ; => #P"/foo/bar/"
(host-kit:ensure-absolute-pathname "bar.txt" "/foo/")  ; => #P"/foo/bar.txt"
(host-kit:parent-directory-pathname "/foo/bar/")       ; => #P"/foo/"

;; Filesystem.
(host-kit:file-exists-p "README.md")        ; => truename, or NIL
(host-kit:directory-exists-p "src/")        ; => truename, or NIL
(host-kit:file-readable-p "README.md")      ; => truename, or NIL
(host-kit:file-writable-p "state.txt")      ; => truename, or NIL
(host-kit:file-executable-p "/usr/bin/env") ; => truename, or NIL
(host-kit:directory-files "src/")           ; => list of file pathnames
(host-kit:subdirectories ".")               ; => list of directory pathnames
(host-kit:directory-empty-p "scratch/")     ; => T only when no direct entries exist
(host-kit:file-metadata "README.md")        ; => read-only kind/size/mode value
(host-kit:symbolic-link-p "current")         ; => T or NIL
(host-kit:read-file-string "README.md")     ; => the whole file as a string
(host-kit:read-file-lines "README.md")      ; => list of lines
(host-kit:ensure-directory-tree "var/cache/app/") ; creates missing parents
(host-kit:write-file-string "updated" "state.txt") ; atomically replaces target
(host-kit:write-file-lines '("first" "second") "state.txt") ; atomic text lines
(host-kit:read-file-octets "asset.bin")     ; => an unsigned-byte 8 vector
(host-kit:temporary-directory)              ; => #P"/tmp/"
(host-kit:with-temporary-directory (directory)
  (format nil "~Aoutput.txt" directory))    ; directory is removed afterwards
(host-kit:delete-file-if-exists "state.txt") ; => T when a regular file was removed
(host-kit:delete-empty-directory "scratch/") ; removes an empty directory

;; Programs: direct argv execution, no shell parsing.
(host-kit:process-result-stdout
 (host-kit:run-program "/bin/echo" '("hello"))) ; => "hello\n"
(host-kit:ensure-program-success
 (host-kit:run-program "/bin/true" '()))        ; => process-result

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
