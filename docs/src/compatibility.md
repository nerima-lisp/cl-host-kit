# Migrating from uiop

`cl-host-kit` is not a UIOP compatibility layer. It exposes a small,
SBCL-focused host API with its own contracts, direct argument shapes, and
structured failure conditions. Migrate each call deliberately rather than
changing a package prefix mechanically.

## Direct replacements

| UIOP operation | `host-kit` operation | Migration note |
| --- | --- | --- |
| `uiop:getenv` | `getenv` | A string name returns a string or `NIL`. |
| `(setf uiop:getenv)` | `(setf getenv)` | A `NIL` value unsets the variable. |
| `uiop:command-line-arguments` | `command-line-arguments` | Returns a fresh list without the executable name. |
| `uiop:hostname` | `hostname` | Returns the implementation's host name. |
| `uiop:quit` | `quit` | Optional exit code, defaulting to zero. |
| `uiop:getcwd` | `getcwd` | Returns a directory-form pathname. |
| `uiop:chdir` | `chdir` | Changes process-global working directory. Prefer `with-working-directory` for scoped use. |
| `uiop:absolute-pathname-p` | `absolute-pathname-p` | Direct predicate. |
| `uiop:directory-pathname-p` | `directory-pathname-p` | Direct predicate. |
| `uiop:ensure-pathname` | `ensure-pathname` | Only the pathname designator is accepted. |
| `uiop:ensure-directory-pathname` | `ensure-directory-pathname` | Direct pathname conversion. |
| `uiop:ensure-absolute-pathname` | `ensure-absolute-pathname` | Optional defaults is positional; no UIOP keyword options are accepted. |
| `uiop:pathname-directory-pathname` | `pathname-directory-pathname` | Strips name and type. |
| `uiop:pathname-parent-directory-pathname` | `parent-directory-pathname` | The name is intentionally shorter; a filesystem root is its own parent. |
| `uiop:truenamize` | `truenamize` | Resolves existing parents without failing for a missing leaf. |
| `uiop:file-exists-p` | `file-exists-p` | Returns a truename for regular files, otherwise `NIL`. |
| `uiop:directory-exists-p` | `directory-exists-p` | Returns a truename for directories, otherwise `NIL`. |
| `uiop:directory-files` | `directory-files` | Lexical-order direct regular-file listing, including dotfiles. |
| `uiop:subdirectories` | `subdirectories` | Lexical-order direct directory listing, including dot-directories. |
| `uiop:delete-file-if-exists` | `delete-file-if-exists` | Deletes only a regular file and returns a generalized boolean. |
| `uiop:delete-empty-directory` | `delete-empty-directory` | Removes an empty directory; a nonempty directory signals a host error. |
| `uiop:delete-directory-tree` | `delete-directory-tree` | Supports only `:validate` and `:if-does-not-exist`. |
| `uiop:rename-file-overwriting-target` | `(move-path source target :if-exists :supersede)` | Explicitly opts into POSIX replacement semantics. |
| `uiop:temporary-directory` | `temporary-directory` | Honors a non-empty absolute `TMPDIR`; otherwise uses `/tmp/`. |
| `uiop:read-file-string` | `read-file-string` | Reads the whole file. |
| `uiop:read-file-lines` | `read-file-lines` | Reads text lines, with optional `:external-format`. |
| `uiop:copy-file` | `copy-file` | Uses an atomic target and requires `:if-exists :supersede` to replace. |
| `uiop:split-string` | `split-string` | `:separator` accepts characters, a string, or one character; `:max` is not supported. |
| `uiop:string-prefix-p` | `string-prefix-p` | Direct predicate. |

## Process boundary

Replace a synchronous `uiop:run-program` call with
`(run-program program arguments ...)`, where `program` is a path or executable
name and `arguments` is a list of strings. The command is always executed
without a shell, stdout and stderr are captured, the default deadline is 30
seconds, and nonzero exits remain result data. Call `ensure-program-success`
where a nonzero exit must signal an error.

`launch-program`, `wait-process`, `terminate-process`, `process-alive-p`, and
other asynchronous lifecycle APIs are intentionally absent. Use
[`cl-process-kit`](https://github.com/nerima-lisp/cl-process-kit) for process
handles, supervision, or concurrent process orchestration.

## Temporary files

Use `call-with-temporary-file` or `with-temporary-file` instead of preserving
the UIOP macro shape. HOST-KIT's forms bind a stream and pathname, close the
stream on every exit path, and remove the file unless `:keep` is true (or its
zero-argument predicate returns true after normal completion). Use
`call-with-temporary-directory` or `with-temporary-directory` for the matching
directory lifecycle.

## Failure handling

OS-facing operations signal `host-operation-failed` rather than raw UIOP,
`sb-posix`, or `file-error` conditions. Process deadline and exit-boundary
failures are represented by `process-timeout` and `process-exit-error`.
Catch their common superclass, `host-kit-error`, when the caller needs one
library-level failure boundary.
