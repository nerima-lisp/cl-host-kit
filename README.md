# cl-host-kit

[![CI](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-host-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-host-kit/)

An SBCL-native host-environment toolkit: pathname coercion and predicates,
filesystem checks and non-recursive listing, scoped temporary resources, atomic
whole-file I/O, environment-variable read/write, timeout-bounded direct program
execution, and the string helpers that go with them. Unlike `uiop`, it is not a
portability layer: every function takes only its documented arguments, returns
concrete Common Lisp values, and signals a structured condition on failure.
SBCL's own `sb-posix` contrib is the only dependency.

Full documentation is published at <https://nerima-lisp.github.io/cl-host-kit/>.
The source for that site lives in [docs/src/](docs/src/).

## Quick Start

Every OS-facing operation is scoped and restores what it changed, and every
failure arrives as one condition type rather than a raw `sb-posix` error:

```lisp
(asdf:load-system "cl-host-kit")

(host-kit:with-environment-variables (("MODE" "test"))
  (host-kit:with-working-directory ("/tmp/")
    (host-kit:write-file-string "generated" "state.txt") ; atomic replace
    (handler-case (host-kit:read-file-string "missing.txt")
      (host-kit:host-kit-error (c)
        (format nil "~a failed on ~a"
                (host-kit:host-operation-failed-operation c)
                (host-kit:host-operation-failed-target c))))))
;; => "read-file-string failed on /tmp/missing.txt"
;; MODE and the working directory are both restored, including on non-local exit.
```

`getenv`/`(setf getenv)` and `getcwd`/`chdir` operate on process-global state.
The scoped helpers restore it reliably on normal and non-local exits, but
callers using threads must provide their own process-wide exclusion.

## Install

```nix
# flake.nix
inputs.cl-host-kit = {
  url = "github:nerima-lisp/cl-host-kit/v0.2.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org must pin a release tag rather
than follow the default branch. Outside Nix, put the repository where ASDF can
find it and `(asdf:load-system "cl-host-kit")`.

## Documentation

- [Getting started](https://nerima-lisp.github.io/cl-host-kit/getting-started/)
- [API reference](https://nerima-lisp.github.io/cl-host-kit/reference/api/)
- [Migrating from uiop](https://nerima-lisp.github.io/cl-host-kit/reference/compatibility/)
  — direct replacements, and the UIOP concepts deliberately not supported.

Two boundaries worth knowing before you read further. `run-program` takes a
direct argv list and never shell text, captures stdout and stderr without pipe
deadlock, and kills an isolated child process group at its 30-second default
deadline; for asynchronous process handles and supervision, use
[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit) instead. Atomic
writes and binary copies preserve an existing regular target's permission bits,
and `:synchronize t` additionally `fsync`s the data, the metadata, and the
containing directory before returning.

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework.

```sh
nix run .#bench      # microbenchmarks
nix run .#coverage   # SBCL/SB-COVER HTML report; the `coverage` check gates it
```

Each benchmark case targets 20 ms of work before three warmups and seven
samples, capped at 250 operations, with full GCs bracketing both phases so
their cost stays out of individual samples. Select one group with
`CL_HOST_KIT_BENCHMARK=splits|pathnames|filesystem`. The runner also compares
result-equivalent operations against ASDF's bundled `uiop`, which is loaded by
the benchmark only and never by the library system; a figure below `1.00x`
means cl-host-kit used less time or allocation in that local run, not that it
is universally faster.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide, the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md),
and this repository's own
[development page](https://nerima-lisp.github.io/cl-host-kit/project/development/)
for the source layout and conventions.

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
