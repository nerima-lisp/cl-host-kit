# API Reference

All symbols below live in the `host-kit` package (`src/package.lisp` is the
single source of truth for what is exported).

## Conditions

`src/conditions.lisp`

- **`host-kit-error`** — Base condition for every error `cl-host-kit`
  signals. Subtype of `error`.
- **`host-operation-failed`** (`operation` `target` `reason`) — Signalled
  when an underlying OS call fails. `host-operation-failed-operation` is a
  keyword naming the attempted operation; `host-operation-failed-target` is
  the pathname or string it was attempted on (or `NIL`);
  `host-operation-failed-reason` is the underlying condition that caused the
  failure.
## Environment and process lifecycle

`src/environment.lisp`

- **`(getenv name)`** — Return the value of environment variable `name` as
  a string, or `NIL` if unset.
- **`(setf (getenv name) value)`** — Set `name` to `value` (a string); a
  `value` of `NIL` unsets it instead.
- **`(quit &optional (code 0))`** — Terminate the current process with
  `code`. Never returns.

## Working directory

`src/working-directory.lisp`

- **`(getcwd)`** — Return the current working directory as a directory-form
  pathname.
- **`(chdir pathspec)`** — Change the current working directory to
  `pathspec` (a pathname designator).

Environment variables and the current directory are process-global state.
The scoped APIs restore the previous state with `unwind-protect`, including
on non-local exit. They do not serialize concurrent callers; threaded
programs must provide process-wide exclusion around state-changing calls.

## Pathnames

`src/pathnames.lisp`

- **`(absolute-pathname-p pathspec)`** — True when `pathspec` denotes an
  absolute path.
- **`(directory-pathname-p pathspec)`** — True when `pathspec` has neither a
  name nor a type component.
- **`(ensure-pathname pathspec)`** — Coerce `pathspec` into a `pathname`.
- **`(ensure-directory-pathname pathspec)`** — Return a directory-form
  pathname for `pathspec`, folding any name/type into the directory.
- **`(ensure-absolute-pathname pathspec &optional (defaults *default-pathname-defaults*))`**
  — Return an absolute pathname for `pathspec`, merging against `defaults`
  when relative.
- **`(pathname-directory-pathname pathspec)`** — Return the directory-only
  portion of `pathspec`.
- **`(truenamize pathspec)`** — Return a canonical, absolute form of
  `pathspec`, resolving the closest existing parent and preserving all
  missing trailing components; unlike `truename`, does not error when
  `pathspec` does not (yet) exist.

## Filesystem

`src/filesystem.lisp`

- **`(file-exists-p pathspec)`** — Return the truename of `pathspec` if it
  exists and is not a directory, else `NIL`.
- **`(directory-exists-p pathspec)`** — Return the truename of `pathspec` if
  it exists and is a directory, else `NIL`.
- **`(directory-files pathspec)`** — Return the regular files directly
  inside directory `pathspec` (non-recursive).
- **`(subdirectories pathspec)`** — Return the immediate subdirectories of
  directory `pathspec` (non-recursive).
- **`(delete-directory-tree pathspec &key validate (if-does-not-exist :error))`**
  — Recursively delete directory `pathspec`. `if-does-not-exist` is
  `:error` (default) or `:ignore`. `validate`, when true, requires
  `pathspec` to already be directory-form before anything is deleted.
- **`(rename-file-overwriting-target source target)`** — Rename `source` to
  `target`, atomically replacing `target` if it exists.
- **`(temporary-directory)`** — Return the system temporary directory,
  honoring `TMPDIR`.
- **`(read-file-string pathspec)`** — Return the entire UTF-8 contents of the
  file `pathspec` as a string. Read and decoding failures signal
  `host-operation-failed` with `:read-file-string` as its operation; the
  underlying decoding condition is available through
  `host-operation-failed-reason`.

## Strings

`src/strings.lisp`

- **`(split-string string &key (separator #\Space))`** — Split `string`
  wherever any character in `separator` (a list of characters, a string, or
  a single character) appears. Consecutive separator characters produce
  empty-string segments between them.
- **`(string-prefix-p prefix string)`** — True when `string` starts with
  `prefix`.
