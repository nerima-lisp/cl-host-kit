# cl-host-kit

[![CI](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml)
[![Publish documentation](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/docs.yml/badge.svg)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An SBCL-native host-environment toolkit for Common Lisp: pathname
coercion and predicates, filesystem existence checks and non-recursive
listing, a temporary directory, environment-variable read/write, and the
string helpers that go with them. It exposes a documented, deliberately
narrow subset of UIOP-shaped operations, with SBCL's `sb-posix` as the only
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
(host-kit:split-string "a,b,,c" :separator ",") ; => ("a" "b" "" "c")

(setf (host-kit:getenv "MY_VAR") "1")           ; set
(setf (host-kit:getenv "MY_VAR") nil)           ; unset
```

Every function that touches the OS wraps its failure in a structured
`host-operation-failed` condition carrying `:operation`, `:target`, and
`:reason`, so a caller can catch every HOST-KIT failure with one
`handler-case` clause on `host-kit-error`. See
[API Reference](https://nerima-lisp.github.io/cl-host-kit/api-reference/)
for the full surface.

`getenv`/`(setf getenv)` and `getcwd`/`chdir` operate on process-global
state. Scoped helpers restore state reliably on normal and non-local exits,
but callers that use threads must provide their own process-wide exclusion.

## Why another host/filesystem library?

**A deliberately narrow contract, not uiop's full surface.**
`uiop`'s pathname and filesystem functions accept a long tail of keyword
arguments (`:want-pathname`, `:want-directory`, `:defaults`, ...). HOST-KIT
specifies and tests only the supported argument shapes instead of the full
kitchen sink. See
[Compatibility](https://nerima-lisp.github.io/cl-host-kit/compatibility/)
for the supported mappings; audit a dependent project before replacing a
`uiop:` dependency.

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
- **SBCL-native.** The system depends directly on SBCL's `sb-posix` contrib;
  it is intentionally not loadable on other Common Lisp implementations.

## Develop

```sh
nix run .#test
nix flake check --print-build-logs
```

Run repeatable microbenchmarks. Each case targets 20 ms of work before collecting three warmups and seven samples, with a per-case cap of 250 operations. Full garbage collections bracket the warmup and measurement phases, keeping their cost out of individual samples:

```sh
nix run .#bench
```

To investigate one hot path without running the full suite, select a group with
`CL_HOST_KIT_BENCHMARK`: `splits`, `pathnames`, or `filesystem`.

```sh
CL_HOST_KIT_BENCHMARK=pathnames nix run .#bench
```

The runner also compares selected, result-equivalent operations against ASDF's
bundled `uiop` implementation. `uiop` is loaded only by the benchmark, never
by the library system. Each comparison checks that both implementations return
the same result before timing; operations with incompatible calling conventions
are not compared. A relative value below `1.00x` means HOST-KIT used less time
or allocation in that local run, not that it is universally fastest.

Generate an SBCL/SB-COVER HTML coverage report in a temporary directory:

```sh
nix run .#coverage
```

The flake `coverage` check verifies that the report is generated.

`nix flake check` also runs the formatting gate and builds the
documentation. [Contributing](https://nerima-lisp.github.io/cl-host-kit/contributing/)
covers the source layout and conventions.

## License

MIT. See [LICENSE](LICENSE).
