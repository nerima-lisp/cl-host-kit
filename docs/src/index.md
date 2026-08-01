# cl-host-kit

`cl-host-kit` is an **SBCL-native host-environment toolkit for Common
Lisp**. It provides pathname coercion and predicates, filesystem existence
checks and non-recursive listing, a temporary directory, environment-variable
read/write, process termination, and the two string helpers that go with
them.

The library targets SBCL only. Every OS-facing function is built on SBCL's
`sb-posix` contrib or plain Lisp file operations. Its only implementation
dependency is `sb-posix`; it does not depend on `uiop`.

Start with [Getting Started](getting-started.md), then see
[Why cl-host-kit](guide/why.md) for the scope decisions,
[Compatibility with uiop](reference/compatibility.md) for exactly which uiop
symbols map to which `host-kit` function, and the
[API Reference](reference/api.md) for the full surface.

## Contributing and support

Contributions are welcome. [Development](project/development.md) covers the
`nix develop` loop, the test, benchmark and coverage commands, and the
conventions the codebase follows.

Everything else is org-wide and lives in
[`nerima-lisp/.github`](https://github.com/nerima-lisp/.github): the
[contribution guide](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md),
the [code of conduct](https://github.com/nerima-lisp/.github/blob/main/CODE_OF_CONDUCT.md),
the [security policy](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md),
and [support](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
Bugs and questions go to the
[issue tracker](https://github.com/nerima-lisp/cl-host-kit/issues).
