# Compatibility with uiop

`cl-host-kit` implements a deliberately narrow, SBCL-native subset of
`uiop`. This page specifies the public `cl-host-kit` contract; it does not
claim drop-in compatibility with UIOP or establish migration compatibility
for another project. Audit that project's call sites before replacing a
`uiop:` dependency.

| uiop | `host-kit` | Notes |
| --- | --- | --- |
| `uiop:getenv` | `getenv` | Identical: one string argument, string-or-NIL result. |
| `(setf uiop:getenv)` | `(setf getenv)` | Identical: a `NIL` value unsets the variable. |
| `uiop:quit` | `quit` | Identical: optional exit code, defaults to 0. |
| `uiop:getcwd` | `getcwd` | Identical: zero arguments, directory-form pathname result. |
| `uiop:chdir` | `chdir` | Identical: one pathname-designator argument. |
| `uiop:absolute-pathname-p` | `absolute-pathname-p` | Identical. |
| `uiop:directory-pathname-p` | `directory-pathname-p` | Identical. |
| `uiop:ensure-pathname` | `ensure-pathname` | **Narrowed.** Takes exactly one argument and behaves like `(pathname designator)`. UIOP keyword arguments are out of scope. |
| `uiop:ensure-directory-pathname` | `ensure-directory-pathname` | Identical: one pathname-designator argument. |
| `uiop:ensure-absolute-pathname` | `ensure-absolute-pathname` | **Narrowed.** Optional `defaults` is accepted only positionally, with no other keyword arguments. |
| `uiop:pathname-directory-pathname` | `pathname-directory-pathname` | Identical. |
| `uiop:truenamize` | `truenamize` | Resolves the closest existing parent and preserves any missing suffix without signalling for a missing target. |
| `uiop:file-exists-p` | `file-exists-p` | Identical. |
| `uiop:directory-exists-p` | `directory-exists-p` | Identical. |
| `uiop:directory-files` | `directory-files` | Identical: non-recursive, files only. |
| `uiop:subdirectories` | `subdirectories` | Identical: non-recursive, directories only. |
| `uiop:delete-directory-tree` | `delete-directory-tree` | **Narrowed.** Supports `:validate` and `:if-does-not-exist` only. Do not assume other UIOP keyword arguments or edge cases are compatible. |
| `uiop:rename-file-overwriting-target` | `rename-file-overwriting-target` | Identical in observable behavior (atomic overwrite), built on `sb-posix:rename` (POSIX `rename(2)`) rather than `cl:rename-file`. |
| `uiop:temporary-directory` | `temporary-directory` | Identical: zero arguments, honors `TMPDIR`. |
| `uiop:read-file-string` | `read-file-string` | Identical: one argument, whole file as a string. |
| `uiop:split-string` | `split-string` | **Narrowed.** `:max` is not implemented. `:separator` accepts a character, list of characters, or string; each character is an independent delimiter. |
| `uiop:string-prefix-p` | `string-prefix-p` | Identical. |

## Deliberately out of scope

**Process launching** (`uiop:run-program`, `uiop:launch-program`,
`uiop:process-alive-p`, and friends) is not implemented here. That is
[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit)'s domain,
and it already covers this ground with a timeout-aware, process-group-safe
API well beyond uiop's original scope.

**`uiop:command-line-arguments`** is not implemented. Use SBCL's
`sb-ext:*posix-argv*` where that is appropriate.

**`uiop:with-temporary-file`** is not part of this production API.
