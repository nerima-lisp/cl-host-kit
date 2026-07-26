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
sbcl --script run-tests.lisp
```

Or reproducibly, as a Nix derivation (this is what CI runs):

```sh
nix flake check
```

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
| `src/pathnames.lisp` | Pathname coercion and predicates. |
| `src/environment.lisp` | `getenv`, `(setf getenv)`, `quit`. |
| `src/working-directory.lisp` | `getcwd`, `chdir`. |
| `src/filesystem.lisp` | Existence checks, listing, deletion, renaming, temp directory, file reads. |

## Conventions

- **Scope is call-site-driven, not uiop-driven.** Before adding a new
  function or a new keyword argument to an existing one, check
  [Compatibility](compatibility.md) — the rule this library follows is "a
  real call site in nerima-lisp needs it," not "uiop has it."
- **Every OS-facing function wraps failures.** Use the `%with-host-operation`
  macro from `src/conditions.lisp` so failures surface as
  `host-operation-failed` rather than a raw `sb-posix` or `file-error`
  condition.
- **SBCL only, paired `#+sbcl`/`#-sbcl` definitions.** Every exported
  function needs both: the real `#+sbcl` implementation, and a `#-sbcl`
  definition that calls `%unsupported`. See any existing function in
  `src/environment.lisp` or `src/working-directory.lisp` for the pattern.
- **Zero external dependencies.** The main system depends on nothing beyond
  SBCL's own `sb-posix` contrib. Before adding anything else, see
  `.github/DEPENDENCY_POLICY.md` in the
  [`nerima-lisp/.github`](https://github.com/nerima-lisp/.github) repository
  for the org-wide policy this project follows.

## Reporting issues

Use the [issue tracker](https://github.com/nerima-lisp/cl-host-kit/issues)
for bugs and questions.
