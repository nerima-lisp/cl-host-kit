# cl-host-kit

[![CI](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml)
[![Publish documentation](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/docs.yml/badge.svg)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A dependency-free host-environment toolkit for Common Lisp: pathname
coercion and predicates, filesystem existence checks and non-recursive
listing, temporary files and directories, environment-variable read/write, and the
string helpers that go with them. It replaces the corner of `uiop` that
nerima-lisp's own code actually calls, with SBCL's `sb-posix` as the only
implementation dependency.

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
(host-kit:getcwd)                               ; => #P"/Users/ada/project/"
(host-kit:file-exists-p "README.md")            ; => #P".../README.md" or NIL
(host-kit:directory-files "src/")               ; => list of file pathnames
(host-kit:read-file-string "README.md")         ; => the whole file as a string
(host-kit:with-temporary-file (:stream stream :pathname pathname)
  (write-string "generated data" stream)
  :close-stream
  (host-kit:read-file-string pathname))          ; => "generated data"
(host-kit:split-string "a,b,,c" :separator ",") ; => ("a" "b" "" "c")
(host-kit:split-string "a,b,c,d" :separator "," :max 3)
; => ("a" "b" "c,d")

(setf (host-kit:getenv "MY_VAR") "1")           ; set
(setf (host-kit:getenv "MY_VAR") nil)           ; unset

(host-kit:with-environment-variables (("LOG_LEVEL" "debug"))
  (host-kit:getenv "LOG_LEVEL"))                 ; => "debug", then restored
```

Every function that touches the OS wraps its failure in a structured
`host-operation-failed` condition carrying `:operation`, `:target`, and
`:reason`, so a caller can catch every HOST-KIT failure with one
`handler-case` clause on `host-kit-error`. See
[API Reference](https://nerima-lisp.github.io/cl-host-kit/api-reference/)
for the full surface.

## Why another host/filesystem library?

**Scoped to what nerima-lisp actually calls, not uiop's full surface.**
`uiop`'s pathname and filesystem functions accept a long tail of keyword
arguments (`:want-pathname`, `:want-directory`, `:defaults`, ...) that an
org-wide call-site survey found unused anywhere in this org. HOST-KIT
implements the narrower contract those call sites actually rely on instead
of the full kitchen sink — see
[Compatibility](https://nerima-lisp.github.io/cl-host-kit/compatibility/)
for exactly which uiop symbols map to which HOST-KIT function.

**Not a grab bag.** Process launching (`uiop:run-program` and friends) is
deliberately out of scope — that is
[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit)'s job, and
it already does it better than uiop did.

## What you also get

- **Structured diagnostics.** Every OS-facing function signals
  `host-operation-failed` (carrying the failed operation, target, and
  underlying reason) instead of leaking a raw `sb-posix` or `file-error`
  condition.
- **A documented, minimal contract.** Each function's docstring states
  exactly the argument and return shape it supports — no undocumented
  keyword arguments inherited from uiop's original signatures.
- **SBCL-only, honestly.** Every exported function still has a `#-sbcl`
  definition, so loading this system under another implementation fails
  with one clear `unsupported-implementation` condition per call, rather
  than an undefined-function error at some unrelated call site.

## Develop

```sh
sbcl --script run-tests.lisp   # or: nix flake check
```

`nix flake check` also runs the formatting gate and builds the
documentation. [Contributing](https://nerima-lisp.github.io/cl-host-kit/contributing/)
covers the source layout and conventions.

## License

MIT. See [LICENSE](LICENSE).
