# Development

This page covers the development workflow, how to run the tests and
benchmarks, and the conventions the codebase follows. The org-wide
contribution guide, code of conduct, security policy and support channels
live in [`nerima-lisp/.github`](https://github.com/nerima-lisp/.github); see
the [home page](../index.md#contributing-and-support) for the links.

## Development environment

The repository is a Nix flake:

```sh
nix develop
```

If you use [direnv](https://direnv.net/), `direnv allow` loads it
automatically. If you prefer a local SBCL, ensure `cl-host-kit` (and, for
the tests, `cl-weave`) are visible to ASDF, then load the system:

```lisp
(asdf:load-system "cl-host-kit")
```

## Running the tests

From a checkout:

```sh
nix run .#test
```

Or reproducibly, as a Nix derivation (this is what CI runs):

```sh
nix flake check
```

Test and coverage entry points enforce a 300-second timeout, followed by a
15-second graceful-termination window. The benchmark entry point uses a
120-second timeout. Use `nix flake check --print-build-logs` in CI or when
diagnosing a failure.

### Microbenchmarks

The repeatable microbenchmark runner targets 100 ms per case, then reports
medians after three warmups and 16 measured samples (the sample count must
stay even, for balanced ABBA ordering). A 1,000,000-operation cap bounds
calibration, while full garbage collections bracket the warmup and
measurement phases so their cost stays out of individual samples. It is a
diagnostic tool, not a CI performance gate:

```sh
nix run .#bench
```

Set `CL_HOST_KIT_BENCHMARK` to `splits`, `joins`, `pathnames`, `environment`,
`process`, or `filesystem` to investigate one hot-path group:

```sh
CL_HOST_KIT_BENCHMARK=pathnames nix run .#bench
```

Selected cases also compare against ASDF's bundled `uiop` implementation and,
where relevant, an embedded copy of the previous `cl-host-kit`
implementation. The benchmark verifies equal results before measuring and
excludes APIs whose calling conventions cannot be aligned. `uiop` is a
benchmark-only baseline, not a dependency of `cl-host-kit`; a relative value
below `1.00x` reports a lower local measurement, not a universal performance
claim.

### Coverage

Generate an SBCL/SB-COVER HTML report in a temporary directory:

```sh
nix run .#coverage
```

The flake `coverage` check verifies report generation.

The test system (`cl-host-kit/test`) uses [`cl-weave`](https://github.com/nerima-lisp/cl-weave)
and lives under `t/`, one test file per `src/` file.

## Source layout

`src/` is loaded serially by
[`cl-host-kit.asd`](https://github.com/nerima-lisp/cl-host-kit/blob/main/cl-host-kit.asd):

| File | Contents |
| --- | --- |
| `src/package.lisp` | The single public package. |
| `src/conditions.lisp` | `host-kit-error` and its subtypes, and the `%with-host-operation` wrapping macro. |
| `src/with-macros.lisp` | `define-with-macro`, the macro-defining-macro every `WITH-X` scope macro is generated from. |
| `src/strings.lisp` | `split-string`, `string-prefix-p`. |
| `src/pathnames.lisp` | Pathname coercion, predicates, and parent-directory calculation. |
| `src/environment.lisp` | Environment variables, command-line arguments, hostname, and `quit`. |
| `src/process-result.lisp` | The `process-result` data model, exit-code validation, and PATH-based program lookup. |
| `src/process-io.lisp` | The concurrent stdout/stderr capture and stdin production engine `process.lisp` orchestrates. |
| `src/process.lisp` | `run-program` and its `WITH-X` scope macros: the public process-execution API. |
| `src/working-directory.lisp` | `getcwd`, `chdir`, and serialized scoped directory changes. |
| `src/filesystem-metadata.lisp` | Metadata, symbolic links, permission bits, timestamps, and existence predicates. |
| `src/directory-operations.lisp` | Directory listing/traversal, creation, deletion, and renaming. |
| `src/temporary-resources.lisp` | Temporary directory and file lifecycles. |
| `src/file-io.lisp` | Whole-file reads, line reads, atomic writes, and directory-tree copying. |
| `src/file-locking.lisp` | Scoped advisory file locks with timeout handling. |

## Conventions

- **Keep the public contract direct.** Do not copy UIOP signatures or add
  compatibility-only keyword arguments. Add a host operation only when its
  behavior, ownership, failure mode, and tests can be specified independently
  of UIOP; update [Compatibility](../reference/compatibility.md) when it affects migration.
- **Every OS-facing function wraps failures.** Use the `%with-host-operation`
  macro from `src/conditions.lisp` so failures surface as
  `host-operation-failed` rather than a raw `sb-posix` or `file-error`
  condition.
- **Generate `WITH-X` scope macros, don't hand-write them.** A `CALL-WITH-X`
  thunk-passing function gets its `WITH-X` macro from `define-with-macro`
  (`src/with-macros.lisp`) rather than a bespoke `defmacro`, so the lexical
  bindings, the non-constant-symbol diagnostic, and keyword forwarding are
  written once. Reach for a hand-written macro only when a scope reuses one of
  its own bound variables as a forwarded argument (see
  `with-advisory-file-lock`), which does not fit that shape.
- **CALL-WITH-X is the continuation-passing core; WITH-X is sugar over it.**
  Every scoped resource (a temporary file, a working directory, a held lock,
  a captured environment binding) is implemented once as a `CALL-WITH-X`
  function that takes a thunk (the continuation) and guarantees its
  unwind-protected cleanup runs whichever way the thunk exits; the `WITH-X`
  macro only wraps a lexical body into that thunk. Add the CPS function
  first, then let `define-with-macro` derive the macro -- never the reverse.
- **Separate the data a module operates on from the logic that operates on
  it, and split the file when that separation gets large.** `process.lisp`
  is the reference case: `process-result.lisp` holds the `process-result`
  struct and PATH lookup (the data model), `process-io.lisp` holds the
  concurrent capture/production engine (self-contained logic with no
  awareness of `run-program`'s orchestration), and `process.lisp` holds only
  the orchestration and public API. A struct paired immediately with the
  handful of functions that construct and query it (`file-metadata`,
  `process-result` itself) does not need this split; reach for it once a
  module's registry/struct machinery and its decision logic have each grown
  large enough to be independently readable.
- **SBCL-native implementation.** Use SBCL and its `sb-posix` contrib
  directly. Do not add portability shims or fallback implementations.
- **Zero external dependencies.** The main system depends on nothing beyond
  SBCL's own `sb-posix` contrib. Before adding anything else, see
  `.github/DEPENDENCY_POLICY.md` in the
  [`nerima-lisp/.github`](https://github.com/nerima-lisp/.github) repository
  for the org-wide policy this project follows.
