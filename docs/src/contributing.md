# Contributing

Contributions are welcome. This page covers the development workflow, how
to run the tests, and the conventions the codebase follows.

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

The repeatable microbenchmark runner targets 20 ms per case, then reports
medians after three warmups and seven measured samples. A 250-operation cap
bounds calibration, while full garbage collections bracket the warmup and
measurement phases so their cost stays out of individual samples. It is a
diagnostic tool, not a CI performance gate:

```sh
nix run .#bench
```

Set `CL_HOST_KIT_BENCHMARK` to `splits`, `pathnames`, or `filesystem` to
investigate one hot-path group:

```sh
CL_HOST_KIT_BENCHMARK=pathnames nix run .#bench
```

Selected cases also compare against ASDF's bundled `uiop` implementation. The
benchmark verifies equal results before measuring and excludes APIs whose
calling conventions cannot be aligned. `uiop` is a benchmark-only baseline,
not a dependency of `cl-host-kit`; a relative value below `1.00x` reports a
lower local measurement, not a universal performance claim.

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
| `src/strings.lisp` | `split-string`, `string-prefix-p`. |
| `src/pathnames.lisp` | Pathname coercion, predicates, and parent-directory calculation. |
| `src/environment.lisp` | Environment variables, command-line arguments, hostname, and `quit`. |
| `src/process.lisp` | Program lookup, execution, output capture, and timeout handling. |
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
  of UIOP; update [Compatibility](compatibility.md) when it affects migration.
- **Every OS-facing function wraps failures.** Use the `%with-host-operation`
  macro from `src/conditions.lisp` so failures surface as
  `host-operation-failed` rather than a raw `sb-posix` or `file-error`
  condition.
- **SBCL-native implementation.** Use SBCL and its `sb-posix` contrib
  directly. Do not add portability shims or fallback implementations.
- **Zero external dependencies.** The main system depends on nothing beyond
  SBCL's own `sb-posix` contrib. Before adding anything else, see
  `.github/DEPENDENCY_POLICY.md` in the
  [`nerima-lisp/.github`](https://github.com/nerima-lisp/.github) repository
  for the org-wide policy this project follows.

## Reporting issues

Use the [issue tracker](https://github.com/nerima-lisp/cl-host-kit/issues)
for bugs and questions.
