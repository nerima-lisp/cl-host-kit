# cl-host-kit

`cl-host-kit` is an **SBCL-native host-environment toolkit for Common
Lisp**. It provides pathname coercion and predicates, filesystem existence
checks and non-recursive listing, a temporary directory, environment-variable
read/write, process termination, and the two string helpers that go with
them.

The library targets SBCL only. Every OS-facing function is built on SBCL's
`sb-posix` contrib or plain Lisp file operations. Its only implementation
dependency is `sb-posix`; it does not depend on `uiop`.

Start with [Installation](installation.md) and [Quick Start](quick-start.md),
then see [Compatibility with uiop](compatibility.md) for exactly which uiop
symbols map to which `host-kit` function, and the
[API Reference](api-reference.md) for the full surface.
