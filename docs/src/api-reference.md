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
- **`(call-with-environment-variables bindings thunk)`** — CPS primitive for
  applying `(name value)` pairs while calling `thunk`; restores every original
  value in reverse order after return or failure.
- **`(with-environment-variables ((name value) ...) &body body)`** — Bind
  macro wrapper around `call-with-environment-variables` that evaluates each
  binding form once.
- **`(quit &optional (code 0))`** — Terminate the current process with
  `code`. Never returns.

## Working directory

`src/working-directory.lisp`

- **`(getcwd)`** — Return the current working directory as a directory-form
  pathname.
- **`(chdir pathspec)`** — Change the current working directory to
  `pathspec` (a pathname designator).
- **`(call-with-current-directory pathspec thunk)`** — CPS primitive that
  calls `thunk` after changing to `pathspec`, then restores the directory.
- **`(with-current-directory (pathspec) &body body)`** — Run `body` with
  `pathspec` as the current directory through the CPS primitive.

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
- **`(call-with-temporary-file thunk &key ... attempts)`** — Create a unique
  temporary file, retrying exclusive creation after name collisions up to
  `attempts` (default 128), invoke `thunk` with the requested stream and/or
  pathname, then delete the file unless `:keep` is true.
- **`(with-temporary-file (&key stream pathname directory prefix suffix type keep attempts ...) &body body)`**
  — Bind a temporary file stream and/or pathname for `body`. Place
  `:close-stream` in `body` to run subsequent forms after closing the stream.
- **`(read-file-string pathspec)`** — Return the entire UTF-8 contents of the
  file `pathspec` as a string. Read and decoding failures signal
  `host-operation-failed` with `:read-file-string` as its operation; the
  underlying decoding condition is available through
  `host-operation-failed-reason`.
- **`(call-with-atomic-output-file target thunk &key element-type external-format)`**
  — Call `thunk` with an output stream backed by a temporary file in the target
  directory. After a successful callback, close and atomically replace the
  target; on failure, leave any existing target unchanged and remove the
  temporary file.
- **`(with-atomic-output-file (stream target &key element-type external-format) ...)`**
  — Lexically bind `stream` for an atomic output operation.
- **`(write-file-string string pathspec &key external-format)`** — Atomically
  write `string` to `pathspec` and return its absolute pathname.
- **`(read-file-octets pathspec)`** — Return the entire contents of `pathspec`
  as a vector of `(unsigned-byte 8)`.
- **`(write-file-octets octets pathspec)`** — Atomically write an
  `(unsigned-byte 8)` array to `pathspec` and return its absolute pathname.

## Strings

`src/strings.lisp`

- **`(split-string string &key (separator #\Space))`** — Split `string`
  wherever any character in `separator` (a list of characters, a string, or
  a single character) appears. Consecutive separator characters produce
  empty-string segments between them.
- **`(string-prefix-p prefix string)`** — True when `string` starts with
  `prefix`.
