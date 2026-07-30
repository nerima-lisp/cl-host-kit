# cl-host-kit

[![CI](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml)
[![Publish documentation](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/docs.yml/badge.svg)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A dependency-free host-environment toolkit for Common Lisp: pathname
coercion and predicates, filesystem existence checks and non-recursive
listing, scoped temporary resources, atomic whole-file I/O,
environment-variable read/write, timeout-bounded direct program execution, and
the string helpers that go with them.
It provides a focused, direct API rather than a compatibility layer for
`uiop`, with SBCL's `sb-posix` as the only implementation dependency.

📖 **Documentation: <https://nerima-lisp.github.io/cl-host-kit/>**

## Install

```sh
nix build github:nerima-lisp/cl-host-kit
```

or put the repository where ASDF can find it:

```lisp
(asdf:load-system "cl-host-kit")
```

The library depends on nothing outside of SBCL's own `sb-posix` contrib;
only the test system additionally uses `cl-weave`. SBCL is the supported
implementation — see
[Installation](https://nerima-lisp.github.io/cl-host-kit/installation/).

## Use

```lisp
(host-kit:getenv "HOME")                       ; => "/Users/ada"
(host-kit:with-environment-variable ("MY_VAR" "temporary")
  (host-kit:getenv "MY_VAR"))                   ; restored afterward
(host-kit:with-environment-variables
    (("MODE" "test") ("OPTIONAL_SETTING" nil))
  (host-kit:getenv "MODE"))                     ; validates, scopes, restores all
(host-kit:getcwd)                               ; => #P"/Users/ada/project/"
(host-kit:command-line-arguments)               ; => ("--serve" "8080")
(host-kit:hostname)                             ; => "build-host"
(host-kit:user-id)                              ; => 501
(host-kit:effective-group-id)                   ; => 20
(host-kit:user-name)                            ; => "ada"
(host-kit:effective-group-name)                 ; => "staff"
(host-kit:user-config-directory)                ; => #P"/Users/ada/.config/"
(host-kit:user-cache-directory)                 ; => #P"/Users/ada/.cache/"
(host-kit:with-working-directory ("/tmp/")
  (host-kit:directory-files "."))              ; directory is restored afterward
(host-kit:file-exists-p "README.md")            ; => #P".../README.md" or NIL
(host-kit:file-readable-p "README.md")          ; => #P".../README.md" or NIL
(host-kit:file-writable-p "state.txt")          ; => #P".../state.txt" or NIL
(host-kit:file-executable-p "/usr/bin/env")     ; => #P"/usr/bin/env" or NIL
(host-kit:directory-files "src/")               ; => list of file pathnames
(host-kit:file-metadata "README.md")            ; => read-only kind/size/mode value
(host-kit:set-file-owner "state.txt"
                         :owner-id (host-kit:file-metadata-owner-id
                                    (host-kit:file-metadata "state.txt")))
                                                ; requires host permission
(host-kit:symbolic-link-p "current")             ; => T or NIL
(host-kit:read-file-lines "README.md")          ; => list of lines
(host-kit:parent-directory-pathname "/var/log/app/") ; => #P"/var/log/"
(host-kit:pathname-within-p "/srv/app/cache/state" "/srv/app/") ; => T
(host-kit:relative-pathname "/srv/app/logs/current.txt" "/srv/app/cache/")
                                                ; => #P"../logs/current.txt"
(host-kit:ensure-directory-tree "var/cache/app/") ; creates missing parents
(host-kit:write-file-string "updated" "state.txt") ; atomically replaces target
(host-kit:write-file-lines '("first" "second") "state.txt") ; atomic text lines
(host-kit:move-path "state.txt" "state.previous") ; refuses to replace by default
(host-kit:copy-directory-tree "assets/" "release-assets/") ; staged tree publication
(host-kit:copy-path "current" "current.backup")   ; preserves files, trees, and links
(host-kit:find-program "git")                   ; => #P".../bin/git" or NIL
(host-kit:process-result-stdout
 (host-kit:run-program "/bin/echo" '("hello"))) ; => "hello\n"
(host-kit:ensure-program-success
 (host-kit:run-program "/bin/true" '()))        ; => process-result
(host-kit:split-string "a,b,,c" :separator ",") ; => ("a" "b" "" "c")
(host-kit:join-strings '("build" "cache" "state") :separator "/")
                                                ; => "build/cache/state"

(setf (host-kit:getenv "MY_VAR") "1")           ; set
(setf (host-kit:getenv "MY_VAR") nil)           ; unset
```

Every function that touches the OS wraps its failure in a structured
`host-operation-failed` condition carrying `:operation`, `:target`, and
`:reason`, so a caller can catch every HOST-KIT failure with one
`handler-case` clause on `host-kit-error`. See
[API Reference](https://nerima-lisp.github.io/cl-host-kit/api-reference/)
for the full surface.

## Why another host/filesystem library?

**A direct, deliberately small host API.** HOST-KIT does not emulate UIOP
signatures or keyword-option sets. Its functions accept only the documented
arguments and return concrete Common Lisp values. The
[Migration guide](https://nerima-lisp.github.io/cl-host-kit/compatibility/)
lists direct replacements and intentionally unsupported UIOP concepts.

**A small synchronous command boundary.** `run-program` accepts a direct argv
list, never shell text, captures stdout and stderr without pipe deadlock, and
terminates an isolated child process group at its 30-second default deadline.
Use `ensure-program-success` when a non-zero terminal status must become a
`process-exit-error`; otherwise inspect `process-result` directly.
For asynchronous process handles and supervision, use
[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit).

## What you also get

- **Structured diagnostics.** Every OS-facing function signals
  `host-operation-failed` (carrying the failed operation, target, and
  underlying reason) instead of leaking a raw `sb-posix` or `file-error`
  condition.
- **A documented, minimal contract.** Each function's docstring states
  exactly the argument and return shape it supports — no undocumented
  keyword arguments inherited from uiop's original signatures.
- **Safe atomic replacement.** Atomic writes and binary copies preserve an
  existing regular target's access permission bits while replacing its contents.
  Pass `:synchronize t` to `fsync` replacement data and metadata before rename,
  then `fsync` the containing directory so the replacement itself is durable.
- **SBCL-only, honestly.** Every exported function still has a `#-sbcl`
  definition, so loading this system under another implementation fails
  with one clear `unsupported-implementation` condition per call, rather
  than an undefined-function error at some unrelated call site.

## Develop

```sh
sbcl --script run-tests.lisp   # or: nix flake check
```

Generate an SBCL HTML coverage report for the library sources:

```sh
nix run .#coverage
open coverage/cover-index.html
```

`nix flake check` also runs the formatting gate and builds the
documentation. [Contributing](https://nerima-lisp.github.io/cl-host-kit/contributing/)
covers the source layout and conventions.

## License

MIT. See [LICENSE](LICENSE).
