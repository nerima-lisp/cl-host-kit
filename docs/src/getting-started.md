# Getting Started

## Install with Nix

```sh
nix build github:nerima-lisp/cl-host-kit
```

To pin it as a flake input, follow the same pattern the rest of the
nerima-lisp org uses for sibling packages: pull the source only
(`flake = false`) and pin to a release tag rather than the default branch.

```nix
inputs.cl-host-kit = {
  url = "github:nerima-lisp/cl-host-kit/v0.2.1";
  flake = false;
};
```

## Install with ASDF

Put the repository somewhere ASDF can find it and load it:

```lisp
(asdf:load-system "cl-host-kit")
```

## Dependencies

The main `cl-host-kit` system depends on nothing outside of SBCL's own
`sb-posix` contrib, which is not a separate library to install — it ships
with SBCL itself. The `cl-host-kit/test` system additionally depends on
[`cl-weave`](https://github.com/nerima-lisp/cl-weave), the org's test
framework; that dependency does not affect the shipped library.

## Supported implementation

SBCL only. The system depends directly on SBCL's bundled `sb-posix` contrib,
and is intentionally not loadable on other Common Lisp implementations.

## A tour of the surface

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
(let (pathname)
  (host-kit:with-temporary-file (stream file :keep t)
    (write-string "generated data" stream)
    (setq pathname file))
  (host-kit:read-file-string pathname))     ; => "generated data"
(host-kit:write-file-string "finished output" #P"/tmp/result.txt")
                                             ; => #P"/tmp/result.txt"
(host-kit:write-file-octets
 (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(1 2 3))
 #P"/tmp/payload.bin")
(host-kit:read-file-octets #P"/tmp/payload.bin") ; => #(1 2 3)
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

## Next steps

- [Why cl-host-kit](guide/why.md) for what this library deliberately does not
  do, and how it relates to `uiop` and `cl-boundary-kit`.
- [Compatibility with uiop](reference/compatibility.md) for exactly which uiop
  symbols map to which `host-kit` function.
- [API Reference](reference/api.md) for the full surface.
