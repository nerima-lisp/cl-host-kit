# FAQ

## Why not just depend on uiop directly?

Every `.asd` in nerima-lisp can already reach `uiop:` symbols for free, since
ASDF always loads it — and until this library existed, several repositories
did exactly that without ever declaring it as a dependency. `cl-host-kit`
exists to make that dependency explicit, and to implement only the narrower
contract nerima-lisp's own code actually needs (see
[Compatibility](compatibility.md)) rather than carrying uiop's full surface,
including the ASDF-integration and Lisp-image-lifecycle features this org
never uses.

## Why does `quit` exist when `sb-ext:exit` already does the same thing?

So that code depending on `cl-host-kit` for everything else does not also
need a direct `sb-ext:` reference for the one remaining case, and so its
behavior on a non-SBCL implementation is a clear `unsupported-implementation`
condition rather than an undefined-function error.

## Why does `move-path` use `sb-posix:rename` instead of `cl:rename-file`?

POSIX `rename(2)` already overwrites its destination atomically. Common
Lisp's own `rename-file` does not make that same guarantee portably, and
uiop's own implementation of this function goes through several
implementation-specific code paths to work around that — this library only
targets SBCL, so it can call the underlying syscall directly.

## Why doesn't `delete-directory-tree` or `read-file-string` accept every uiop keyword argument?

Because no call site anywhere in the org uses them. See
[Compatibility](compatibility.md) for exactly which arguments are supported
and why. If a future caller needs one of the dropped keywords, that is a
reason to extend the function — with a minor version bump and a call site to
justify it — not a reason to have implemented the full surface speculatively
up front.

## Does this replace `cl-boundary-kit`?

No. [`cl-boundary-kit`](https://github.com/nerima-lisp/cl-boundary-kit) is a
layer above this one: it turns effects like "read an environment variable"
or "check whether a file exists" into swappable protocols with fake
implementations for tests. `cl-host-kit` is the real, non-fake implementation
those effects can be built on — it has no notion of fakes or protocols of its
own.
