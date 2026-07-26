# Compatibility with uiop

`cl-host-kit` was designed by surveying every `uiop:` call site in every
`src/` directory across the nerima-lisp org and implementing exactly that
union — not uiop's full surface. This page states the mapping and, where the
contract narrows, exactly how.

| uiop | `host-kit` | Notes |
| --- | --- | --- |
| `uiop:getenv` | `getenv` | Identical: one string argument, string-or-NIL result. |
| `(setf uiop:getenv)` | `(setf getenv)` | Identical: a `NIL` value unsets the variable. |
| `uiop:quit` | `quit` | Identical: optional exit code, defaults to 0. |
| `uiop:getcwd` | `getcwd` | Identical: zero arguments, directory-form pathname result. |
| `uiop:chdir` | `chdir` | Identical: one pathname-designator argument. |
| `uiop:absolute-pathname-p` | `absolute-pathname-p` | Identical. |
| `uiop:directory-pathname-p` | `directory-pathname-p` | Identical. |
| `uiop:ensure-pathname` | `ensure-pathname` | **Narrowed.** uiop accepts a long tail of keyword arguments (`:want-pathname`, `:want-directory`, `:want-absolute`, ...); no call site in the org uses any of them, so `host-kit:ensure-pathname` takes exactly one argument and behaves like `(pathname designator)`. |
| `uiop:ensure-directory-pathname` | `ensure-directory-pathname` | Identical: one pathname-designator argument. |
| `uiop:ensure-absolute-pathname` | `ensure-absolute-pathname` | **Narrowed.** uiop's `:defaults` is accepted only positionally here (matching every org call site), with no other keyword arguments. |
| `uiop:pathname-directory-pathname` | `pathname-directory-pathname` | Identical. |
| `uiop:truenamize` | `truenamize` | Identical in observable behavior: resolves symlinks, does not error when the target is missing. |
| `uiop:file-exists-p` | `file-exists-p` | Identical. |
| `uiop:directory-exists-p` | `directory-exists-p` | Identical. |
| `uiop:directory-files` | `directory-files` | Identical: non-recursive, files only. |
| `uiop:subdirectories` | `subdirectories` | Identical: non-recursive, directories only. |
| `uiop:delete-directory-tree` | `delete-directory-tree` | Identical: `:validate` and `:if-does-not-exist` are the only keywords any call site uses. |
| `uiop:rename-file-overwriting-target` | `rename-file-overwriting-target` | Identical in observable behavior (atomic overwrite), built on `sb-posix:rename` (POSIX `rename(2)`) rather than `cl:rename-file`. |
| `uiop:temporary-directory` | `temporary-directory` | Identical: zero arguments, honors `TMPDIR`. |
| `uiop:read-file-string` | `read-file-string` | Identical: one argument, whole file as a string. |
| `uiop:split-string` | `split-string` | **Narrowed.** `:max` is accepted by uiop but used nowhere in the org, so it is not implemented. `:separator` accepts a list of characters or a string (each character an independent delimiter), matching every call site surveyed. |
| `uiop:string-prefix-p` | `string-prefix-p` | Identical. |

## Deliberately out of scope

**Process launching** (`uiop:run-program`, `uiop:launch-program`,
`uiop:process-alive-p`, and friends) is not implemented here. That is
[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit)'s domain,
and it already covers this ground with a timeout-aware, process-group-safe
API well beyond uiop's original scope.

**`uiop:command-line-arguments`** is not implemented. The one call site that
used it (`cl-cli`) only reaches it on non-SBCL implementations, which
nerima-lisp does not support — the code path is unreachable dead code, not a
real dependency to replace.

**`uiop:with-temporary-file`** is not implemented in this release: every use
of it across the org is in test code, not production `src/`, which was this
release's scope. It is a natural candidate for a future release once a
production call site needs it.
