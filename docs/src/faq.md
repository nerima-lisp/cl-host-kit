# FAQ

## Why not just depend on uiop directly?

ASDF makes UIOP readily available, but that does not make its broad API the
right dependency for every SBCL-only application. `cl-host-kit` makes the
SBCL-native host dependency explicit and provides a deliberately narrow
contract (see [Compatibility](compatibility.md)). Applications that require
portability or UIOP's broader API should keep using UIOP directly. Audit each
dependent project before replacing a `uiop:` call.

## Why does `quit` exist when `sb-ext:exit` already does the same thing?

So that code depending on `cl-host-kit` for everything else does not also
need a direct `sb-ext:` reference for the one remaining case. The library is
SBCL-native and does not provide a portability fallback.

## Why is `rename-file-overwriting-target` built on `sb-posix:rename` instead of `cl:rename-file`?

POSIX `rename(2)` already overwrites its destination atomically. Common
Lisp's own `rename-file` does not make that same guarantee portably, and
uiop's own implementation of this function goes through several
implementation-specific code paths to work around that — this library only
targets SBCL, so it can call the underlying syscall directly.

## Why doesn't `delete-directory-tree` or `read-file-string` accept every uiop keyword argument?

The API is deliberately narrow. Supporting additional keys would expand a
surface that this library does not currently specify or test. See
[Compatibility](compatibility.md) for the supported arguments. If a future
caller needs a dropped keyword, extend the function with a minor version bump
and dedicated tests rather than implementing the full surface speculatively.

## Does this replace `cl-boundary-kit`?

No. [`cl-boundary-kit`](https://github.com/nerima-lisp/cl-boundary-kit) is a
layer above this one: it turns effects like "read an environment variable"
or "check whether a file exists" into swappable protocols with fake
implementations for tests. `cl-host-kit` is the real, non-fake implementation
those effects can be built on — it has no notion of fakes or protocols of its
own.
