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
- **`process-timeout`** — Signalled after `run-program` terminates and reaps a
  child process group that exceeded its deadline. Its accessors are
  `process-timeout-program`, `process-timeout-arguments`,
  `process-timeout-seconds`, and `process-timeout-result`; the result contains
  the captured terminal data.
- **`file-lock-timeout`** — Signalled when an advisory lock cannot be acquired
  within an explicit `call-with-advisory-file-lock` timeout. Its
  `file-lock-timeout-seconds` accessor returns the requested timeout.
- **`process-exit-error`** (`program` `arguments` `exit-code` `signal`
  `expected-exit-codes` `result`) — Signalled by `ensure-program-success` when
  a completed result does not have an accepted exit code. Its report never
  includes captured command output. Its accessors are `process-exit-error-program`,
  `process-exit-error-arguments`, `process-exit-error-exit-code`,
  `process-exit-error-signal`, `process-exit-error-expected-exit-codes`, and
  `process-exit-error-result`; use the last to inspect captured output
  deliberately.

## Environment and host identity

`src/environment.lisp`

- **`(getenv name)`** — Return the value of environment variable `name` as
  a string, or `NIL` if unset.
- **`(setf (getenv name) value)`** — Set `name` to `value` (a string); a
  `value` of `NIL` unsets it instead.
- **`(environment-variables)`** — Return a fresh process-environment snapshot
  as `NAME=VALUE` strings. Both the list and its strings may be mutated by the
  caller without changing the process environment; pass the result directly
  to `run-program`'s `:environment` option.
- **`(call-with-environment-variable thunk name value)`** — Call the nullary
  function `thunk` with `name` temporarily set to the string-or-`NIL` value,
  then restore its prior value on every exit path. Returns all values from
  `thunk`.
- **`(with-environment-variable (name value) &body body)`** — Lexically
  scoped macro form of `call-with-environment-variable`.
- **`(call-with-environment-variables thunk bindings)`** — Temporarily install
  every `(name value)` pair in `bindings`, then call the nullary `thunk`.
  `bindings` must be a proper list of proper two-element `(name value)` lists.
  Values are strings or `NIL` (to unset); names must be non-empty POSIX names.
  All bindings are validated before any change, duplicate names are rejected,
  and every prior value is restored on every exit path.
- **`(with-environment-variables ((name value) ...) &body body)`** — Lexically
  scoped macro form of `call-with-environment-variables`; binding expressions
  are evaluated once before the temporary scope begins.
- **`(command-line-arguments)`** — Return a fresh list of arguments supplied
  to the current program, without the executable name.
- **`(hostname)`** — Return the host name reported by the Common Lisp
  implementation.
- **`(user-id)`** — Return the real Unix user ID of the current process.
- **`(group-id)`** — Return the real Unix group ID of the current process.
- **`(effective-user-id)`** — Return the effective Unix user ID of the current
  process.
- **`(effective-group-id)`** — Return the effective Unix group ID of the
  current process.
- **`(user-name)`** — Return the POSIX passwd name for the real Unix user ID
  of the current process.
- **`(group-name)`** — Return the POSIX group name for the real Unix group ID
  of the current process.
- **`(effective-user-name)`** — Return the POSIX passwd name for the effective
  Unix user ID of the current process.
- **`(effective-group-name)`** — Return the POSIX group name for the effective
  Unix group ID of the current process.
- **`(user-home-directory)`** — Return the current user's absolute home
  directory pathname. Uses non-empty `HOME`, otherwise the effective user's
  POSIX passwd entry.
- **`(user-config-directory)`** — Return absolute `XDG_CONFIG_HOME`, or
  `~/.config/`.
- **`(user-data-directory)`** — Return absolute `XDG_DATA_HOME`, or
  `~/.local/share/`.
- **`(user-cache-directory)`** — Return absolute `XDG_CACHE_HOME`, or
  `~/.cache/`.
- **`(user-state-directory)`** — Return absolute `XDG_STATE_HOME`, or
  `~/.local/state/`.
- **`(user-runtime-directory)`** — Return absolute `XDG_RUNTIME_DIR`, or
  `NIL` when it is unavailable.
- **`(quit &optional (code 0))`** — Terminate the current process with
  `code`. Never returns.

Environment variables are process-global state. HOST-KIT serializes its own
`(setf getenv)` and scoped-environment writes, including nested scopes; readers
outside the scope can still observe temporary values. Do not mix these APIs with
uncoordinated foreign environment writes. Prefer `run-program`'s `:environment`
option for child processes.

User-directory functions follow the XDG Base Directory convention. Relative or
empty XDG values are ignored. The returned fallback pathnames are placement
locations only: they are not created or required to exist. Call
`ensure-directories-exist` before writing when needed. `XDG_RUNTIME_DIR` has no
portable fallback, so `user-runtime-directory` returns `NIL` unless it is an
absolute, non-empty environment value.

## Program execution

`src/process.lisp`

- **`+default-command-timeout-seconds+`** — The default `run-program` deadline:
  30 seconds.
- **`+default-command-output-limit+`** — The maximum number of characters
  retained independently for each captured output stream: 1 MiB. The process
  runner continues draining after this limit to prevent pipe deadlock.
- **`process-result`** — Structure returned by a completed command. Its readers
  are `process-result-program`, `process-result-arguments`,
  `process-result-exit-code`, `process-result-signal`,
  `process-result-stdout`, `process-result-stderr`,
  `process-result-timed-out-p`, `process-result-stdout-truncated-p`, and
  `process-result-stderr-truncated-p`. A non-zero exit code is result data, not
  an error.
- **`(find-program program &key (path (getenv "PATH")))`** — Return the
  executable pathname for an explicit path or a bare name searched through
  `path`, or `NIL` if no executable file is found. An empty `PATH` entry means
  the current directory.
- **`(run-program program arguments &key input (timeout +default-command-timeout-seconds+) environment directory (max-output-characters +default-command-output-limit+))`**
  — Run `program` with the proper string list `arguments`, without a shell. Capture
  standard output and error concurrently; each retains at most
  `max-output-characters` while the remainder is still drained. On timeout,
  terminate and reap the isolated process group, then signal `process-timeout`.
  If setup of an input or output worker fails after the child starts, the
  process group is likewise terminated and reaped before that failure is
  propagated.
  If a descendant retains a captured descriptor after its direct parent exits,
  the capture worker is stopped with a finite polling grace period, so it
  cannot extend command completion indefinitely.
  `environment` is a proper list of `NAME=VALUE` strings: names must be nonempty
  and neither names nor values may contain NUL; only the first `=` separates the
  name from the value. `directory` is a string or pathname normalized to an
  absolute directory pathname before start.
- **`(ensure-program-success result &key (expected-exit-codes '(0)))`** — Return
  `result` unchanged when its exit code belongs to the proper list
  `expected-exit-codes`; else
  signal `process-exit-error`. This keeps `run-program` useful for commands
  whose non-zero status is data, while giving callers an explicit success
  boundary. Signals are always unsuccessful.
- **`(call-with-program-result thunk program arguments &rest options)`** — Run
  the command, then call `thunk` with its `process-result`.
- **`(with-program-result (result program arguments &rest options) &body body)`**
  — Lexically scoped macro form of `call-with-program-result`.
- **`(call-with-program-output thunk program arguments &key input (timeout +default-command-timeout-seconds+) environment directory)`**
  — Run the command while calling `thunk` with a channel keyword (`:stdout` or
  `:stderr`) and each output character. Each channel is drained on a dedicated
  thread, so calls from different channels can interleave; callers that update
  shared state must synchronize it. The returned `process-result` has empty
  output strings and false truncation flags because this API does not retain
  command output. An output callback condition terminates and reaps the child
  process group before being re-signalled, so an unbounded producer cannot
  remain blocked on its output pipe.
- **`(with-program-output (channel character program arguments &rest options) &body body)`**
  — Lexically scoped macro form of `call-with-program-output`.
- **`(call-with-program-input thunk program arguments &key (timeout +default-command-timeout-seconds+) environment directory (max-output-characters +default-command-output-limit+))`**
  — Run the command while calling `thunk` on a dedicated worker with its
  writable standard-input stream. The stream closes automatically when the
  callback returns or exits. Standard output and error are retained in the
  returned `process-result` as for `run-program`; callback conditions are
  re-signalled after the child is drained and reaped. On timeout, the child is
  terminated and reaped before `process-timeout` is signalled, which takes
  precedence over a callback condition. When timeout handling closes the input
  stream, completion waits only for a short finite grace period; a callback
  that continues unbounded non-I/O work is detached because Common Lisp
  cannot forcefully cancel arbitrary threads.
- **`(with-program-input (stream program arguments &rest options) &body body)`**
  — Lexically scoped macro form of `call-with-program-input`.
- **`(call-with-program-io input-thunk output-thunk program arguments &key (timeout +default-command-timeout-seconds+) environment directory)`**
  — Run the command with both standard-input and standard-output callbacks.
  `input-thunk` runs on a dedicated worker with the writable input stream;
  `output-thunk` receives `:stdout` or `:stderr` and each character on a
  dedicated reader thread per channel. Output callback calls can interleave,
  so synchronize shared state. The returned `process-result` deliberately has
  empty output strings and false truncation flags. An output callback
  condition terminates and reaps the child process group before being
  re-signalled. An input callback condition is re-signalled after the child is
  drained and reaped. If no output callback fails, a process timeout takes
  precedence over an input callback condition and terminates and reaps the
  child first. As with `call-with-program-input`, timeout handling closes the
  input stream and waits only for a short finite grace period. An input
  callback that continues unbounded non-I/O work is detached because arbitrary
  Common Lisp threads cannot be forcefully cancelled.
- **`(with-program-io (program arguments &rest options) (:input (stream) &body input-body) (:output (channel character) &body output-body))`**
  — Lexically scoped macro form of `call-with-program-io`. The `:input` body
  runs on the dedicated input worker with `stream` bound to standard input;
  the `:output` body runs on the channel reader threads with `channel` and
  `character` bound to each output event. Synchronize shared state used by
  the output body because the two channel readers can interleave.

## Working directory

`src/working-directory.lisp`

- **`(getcwd)`** — Return the current working directory as a directory-form
  pathname.
- **`(chdir pathspec)`** — Change the current working directory to
  `pathspec` (a pathname designator).
- **`(call-with-working-directory thunk pathspec)`** — Call the nullary
  function `thunk` with `pathspec` as the current directory, restoring the
  previous directory on every exit path.  Returns all values from `thunk`.
- **`(with-working-directory (pathspec) &body body)`** — Lexically scoped
  macro form of `call-with-working-directory`.

The working directory is process-global state. `call-with-working-directory`
and `with-working-directory` serialize their own scopes across threads and
allow nesting within a scope, restoring the previous directory on every exit
path. Direct `chdir` calls, and changes made outside HOST-KIT, are not
covered by that serialization and must not run concurrently with a scoped
change. Prefer `run-program`'s `:directory` option when only a child
process needs a different directory.

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
- **`(parent-directory-pathname pathspec)`** — Return the directory-form
  parent of `pathspec`. A filesystem root is its own parent.
- **`(truenamize pathspec)`** — Return a canonical, absolute form of
  `pathspec`, resolving the closest existing parent and preserving all
  missing trailing components; unlike `truename`, does not error when
  `pathspec` does not (yet) exist.
- **`(pathname-within-p pathspec directory &key (resolve-symlinks nil))`** —
  Return true when `pathspec` is `directory` itself or a descendant. Dot
  navigation is normalized. With `resolve-symlinks` true, existing ancestors
  are resolved first, preventing a symbolic-link ancestor from escaping the
  directory; the final path does not need to exist.
- **`(relative-pathname pathspec base)`** — Return `pathspec` as a pathname
  relative to directory `base`. Both arguments are made absolute before their
  pathname components are compared. This is a lexical operation: it does not
  access the filesystem, normalize dot components, or resolve symbolic links.

## Filesystem

Implementation is separated by responsibility: `src/filesystem-metadata.lisp`
for metadata, symbolic links, permissions, and timestamps;
`src/directory-operations.lisp` for discovery and destructive operations;
`src/temporary-resources.lisp` for scoped temporary paths; `src/file-io.lisp`
for whole-file and atomic I/O; and `src/file-locking.lisp` for scoped advisory
locks.

- **`(file-metadata pathspec &key (follow-symlinks t))`** — Return a
  read-only `file-metadata` value for `pathspec`. Its accessors are
  `file-metadata-kind`, `file-metadata-size`, `file-metadata-modification-time`,
  `file-metadata-access-time`, `file-metadata-change-time`,
  `file-metadata-mode`, `file-metadata-device`, `file-metadata-inode`,
  `file-metadata-hard-link-count`, `file-metadata-owner-id`, and
  `file-metadata-group-id`. Kinds include `:regular-file`, `:directory`, and
  `:symbolic-link`; size is bytes, the time values are universal time, and mode
  contains POSIX permission and special bits. Device and inode identify an
  object on its filesystem. With `follow-symlinks` set to `nil`, metadata
  describes the link itself, including a broken link.
- **`(file-metadata-p value)`** — Return true when `value` is a
  `file-metadata` structure.
- **`(symbolic-link-p pathspec)`** — Return true when `pathspec` is a symbolic
  link, including a broken link.
- **`(read-symbolic-link pathspec)`** — Return a symbolic link's raw target
  string without resolving a relative target.
- **`(create-symbolic-link target link-pathspec)`** — Create a symbolic link
  without replacing an existing destination. Relative string targets remain
  relative to the new link.
- **`(create-hard-link source link-pathspec)`** — Create a POSIX hard link
  without replacing an existing destination. Both paths must share a filesystem.
- **`(set-file-mode pathspec mode)`** — Set POSIX permission and special bits
  on `pathspec`, returning its absolute pathname. `mode` must be an integer
  from `0` through `#o7777`; symbolic links are resolved as by POSIX `chmod`.
- **`(set-file-owner pathspec &key owner-id group-id)`** — Set the POSIX owner
  and/or group ID, returning `pathspec` as an absolute pathname. Supply at
  least one non-negative integer ID; an omitted ID retains its current value.
  Symbolic links are resolved as by POSIX `chown`, and the operation requires
  the host permissions needed to change ownership.
- **`(set-file-times pathspec &key access-time modification-time)`** — Set a
  file's access and modification timestamps as non-negative Common Lisp
  universal times, returning its absolute pathname. An omitted timestamp is
  retained; omitting both uses the current system time. Symbolic links are
  resolved as by POSIX `utime`.
- **`(touch-file pathspec &key access-time modification-time)`** — Create an
  empty file when `pathspec` is absent, update its access and modification
  timestamps, and return its absolute pathname. Existing contents are
  retained. Times are non-negative Common Lisp universal times; omitted times
  use the current system time. Symbolic links are resolved as by POSIX `utime`.
  Existing directories, including directories reached through a symbolic link,
  signal `host-operation-failed`.
- **`(path-exists-p pathspec)`** — Return true when `pathspec` names any
  directory entry, including a dangling symbolic link, and `NIL` when it is
  missing, including a path below a non-directory component. Unlike
  `file-exists-p` and `directory-exists-p`, it does not resolve symbolic links.
- **`(file-exists-p pathspec)`** — Return the truename of `pathspec` if it
  exists and is not a directory, else `NIL`.
- **`(directory-exists-p pathspec)`** — Return the truename of `pathspec` if
  it exists and is a directory, else `NIL`.
- **`(create-directory pathspec &key (mode #o777) (if-exists :error))`** —
  Create exactly one directory without creating missing parents, then return
  its truename. `mode` is an integer from `0` through `#o7777` and is subject
  to the process umask. `if-exists` is `:error` or `:ignore`; the latter
  returns an existing directory but still rejects every other existing entry.
- **`(same-file-p left right)`** — Return true when both paths resolve to the
  same filesystem object, identified by their POSIX device and inode values.
  Symbolic links are followed; missing paths and invalid links signal
  `host-operation-failed`.
- **`(directory-empty-p pathspec)`** — Return true when an existing directory
  has no direct entries other than `.` and `..`. Dotfiles count as entries;
  missing paths and non-directories signal `host-operation-failed`.
- **`(file-readable-p pathspec)`** — Return the truename of `pathspec` when
  it is a readable non-directory file for the calling process, else `NIL`.
  Symbolic links are resolved before the POSIX access check.
- **`(file-writable-p pathspec)`** — Return the truename of `pathspec` when
  it is a writable non-directory file for the calling process, else `NIL`.
  Symbolic links are resolved before the POSIX access check.
- **`(file-executable-p pathspec)`** — Return the truename of `pathspec` when
  it is an executable non-directory file for the calling process, else `NIL`.
  Symbolic links are resolved before the access check. These three access
  predicates are advisory; perform the intended operation and handle its
  failure rather than using a prior access check as authorization.
- **`(directory-files pathspec &key (follow-symlinks nil))`** — Return direct
  regular files in lexical order, including dotfiles. Symbolic links and other
  non-regular entries are excluded by default; with `follow-symlinks` true,
  links to regular files are included.
- **`(subdirectories pathspec &key (follow-symlinks nil))`** — Return direct
  subdirectories in lexical order, including dot-directories. Symbolic links
  are excluded by default; with `follow-symlinks` true, links to directories
  are included.
- **`(call-with-directory-entries thunk pathspec &key (follow-symlinks nil))`** —
  Call `thunk` with each direct entry pathname and `file-metadata` in lexical
  order, including dotfiles. Links are reported without following by default;
  setting `follow-symlinks` to true changes the metadata to describe their
  targets. Returning `:stop` ends enumeration. The directory itself is not
  yielded.
- **`(with-directory-entries (pathname metadata pathspec &key follow-symlinks) &body body)`** —
  Macro form of `call-with-directory-entries` that lexically binds the entry
  pathname and its metadata.
- **`(call-with-directory-tree thunk pathspec &key (follow-symlinks nil) max-depth)`** —
  Call `thunk` with each entry pathname, `file-metadata`, and depth below
  `pathspec` in lexical depth-first order, including dotfiles. Links are
  reported but not descended by default. With `follow-symlinks` true,
  directories are identified by device/inode and visited once, so link cycles
  terminate. A callback return of `:skip-subtree` prunes that directory;
  `:stop` ends the walk. `max-depth` is `NIL` or a non-negative integer that
  limits yielded entries to that depth, with the unyielded root at depth zero.
- **`(with-directory-tree (pathname metadata depth pathspec &key follow-symlinks max-depth) &body body)`** —
  Macro form of `call-with-directory-tree` that lexically binds the entry
  pathname, metadata, and depth. The root directory itself is not yielded.
- **`(ensure-directory-tree pathspec)`** — Create the directory denoted by
  `pathspec` and all missing parents, then return its canonical directory
  pathname. An existing regular file at that location signals
  `host-operation-failed`.
- **`(delete-directory-tree pathspec &key validate (if-does-not-exist :error))`**
  — Recursively delete directory `pathspec`. `if-does-not-exist` is
  `:error` (default) or `:ignore`. A symbolic-link root is rejected without
  traversing its target. The filesystem root, including a pathname that
  resolves to it, is rejected. `validate`, when true, requires
  `pathspec` to already be directory-form before anything is deleted. Any
  other `if-does-not-exist` value signals `type-error` before deletion starts.
- **`(delete-file-if-exists pathspec)`** — Delete `pathspec` only when it
  denotes a regular file; return true if a file was removed and `NIL`
  otherwise. Directories are never removed.
- **`(delete-empty-directory pathspec)`** — Remove the empty directory
  `pathspec`. A missing or nonempty directory signals `host-operation-failed`.
- **`(delete-path pathspec &key recursive (if-does-not-exist :error))`** —
  Delete one filesystem entry without following its final symbolic link.
  Directories must be empty unless `recursive` is true; in that case only real
  directories are recursively deleted, while links are always unlinked. The
  filesystem root and pathnames resolving to it are rejected for recursive
  deletion. Set
  `if-does-not-exist` to `:ignore` to return `NIL` for a missing path; the
  default `:error` signals `host-operation-failed`.
- **`(move-path source target &key (if-exists :error))`** — Move `source` to
  the exact target entry without following either final symbolic link.
  `if-exists` is `:error` (default) or `:supersede`. On one filesystem it uses
  POSIX rename, so `:supersede` atomically replaces the target. When rename
  reports a cross-filesystem move, it stages a copy under the target parent,
  publishes it with a target-local rename, then removes the source. That
  fallback is not atomic across both filesystems: if source removal fails,
  both entries remain. The default rejects an existing target but cannot
  prevent a concurrent creator from winning the race.
- **`(temporary-directory)`** — Return the system temporary directory,
  honoring a non-empty absolute `TMPDIR` and falling back to `/tmp/` when it is
  unset, empty, or relative.
- **`(call-with-temporary-directory thunk &key directory (prefix "tmp-") keep (attempts 128))`**
  — Create an owner-only directory beneath `directory` (or the system
  temporary directory), call `thunk` with its directory-form pathname, then
  recursively remove it. Removal also happens when `thunk` signals. `keep`
  may be true or a zero-argument function that returns true after a
  successful call. Names are generated by the operating system; `attempts`
  bounds retries for a rare allocation collision. `prefix` must be a simple
  file-name fragment and cannot contain `/` or NUL.
- **`(with-temporary-directory (pathname &key directory prefix keep attempts) &body body)`**
  — Macro form of `call-with-temporary-directory` that lexically binds
  `pathname` for `body`.
- **`(read-file-string pathspec &key (external-format :utf-8))`** — Return the
  entire contents of `pathspec` as a string decoded with `external-format`.
- **`(call-with-file-string-chunks thunk pathspec &key (external-format :utf-8) (buffer-size 65536))`** —
  Incrementally call `thunk` with each non-empty decoded text chunk in `pathspec`.
  Every chunk is a fresh, exact-length character string and may be retained after
  the callback returns. Returning `:stop` ends enumeration.
- **`(with-file-string-chunks (chunk pathspec &key external-format buffer-size) &body body)`** —
  Macro form of `call-with-file-string-chunks` that lexically binds each chunk.
- **`(read-file-lines pathspec &key (external-format :utf-8))`** — Return the
  text lines in `pathspec` as a list of strings, without line terminators.
- **`(call-with-file-lines thunk pathspec &key (external-format :utf-8))`** —
  Incrementally call `thunk` with each text line in `pathspec`, without its line
  terminator. Returning `:stop` ends enumeration, and the input stream closes on
  every exit path.
- **`(with-file-lines (line pathspec &key external-format) &body body)`** —
  Macro form of `call-with-file-lines` that lexically binds each input line.
- **`(call-with-file-octet-chunks thunk pathspec &key (buffer-size 65536))`** —
  Incrementally call `thunk` with each non-empty binary chunk in `pathspec`.
  Every chunk is a fresh, exact-length `(unsigned-byte 8)` vector and may be
  retained after the callback returns. Returning `:stop` ends enumeration.
- **`(with-file-octet-chunks (chunk pathspec &key buffer-size) &body body)`** —
  Macro form of `call-with-file-octet-chunks` that lexically binds each chunk.
- **`(read-file-octets pathspec)`** — Return the entire contents of `pathspec`
  as an `(unsigned-byte 8)` vector.
- **`(call-with-temporary-file thunk &key directory (prefix "tmp-") (suffix ".tmp") keep (direction :io) (element-type 'character) (external-format :utf-8) (attempts 128) (synchronize nil))`**
  — Create a new temporary file, then call `thunk` with its stream and
  pathname. The stream is closed and the file is removed after normal return
  or an error, unless `keep` is true or evaluates true after a normal return.
  `direction` is one of `:input`, `:output`, or `:io`; `prefix` and `suffix`
    are simple file-name fragments and cannot contain `/` or NUL. With `synchronize`
    true, a successful output stream is flushed and `fsync`ed before it closes.
- **`(with-temporary-file (stream pathname &key directory prefix suffix keep direction element-type external-format attempts synchronize) &body body)`**
  — Lexically scoped macro form of `call-with-temporary-file`.
- **`(call-with-atomic-output-file target thunk &key (element-type 'character) (external-format :utf-8) (synchronize nil) (if-exists :supersede))`**
  — Call `thunk` with an output stream, then atomically replace `target` only
  after the stream closes successfully. Failures leave the old target intact;
  replacing an existing regular file preserves its access permission bits.
    With `synchronize` true, replacement data and metadata are `fsync`ed before
    the atomic rename, then the containing directory is `fsync`ed after it.
    A failure during the final directory synchronization reports the failed
    operation after the replacement is already visible.
  `if-exists` is `:supersede` (the default) or `:error`; `:error` rejects an
  existing target before creating a temporary file, but cannot atomically exclude
  a concurrent target creator.
- **`(with-atomic-output-file (stream target &key element-type external-format synchronize if-exists) &body body)`**
  — Lexically scoped macro form of `call-with-atomic-output-file`.
- **`(write-file-string string pathspec &key (external-format :utf-8) (synchronize nil) (if-exists :supersede))`** —
  Atomically write `string` and return the absolute target pathname.
- **`(write-file-lines lines pathspec &key (external-format :utf-8) (line-terminator #\Newline) (synchronize nil) (if-exists :supersede))`** —
  Atomically write a proper list of strings, appending `line-terminator` after
  each line, then return the absolute target pathname. `line-terminator` may
  be a character or string.
- **`(write-file-octets octets pathspec &key (synchronize nil) (if-exists :supersede))`** — Atomically write an
  `(unsigned-byte 8)` array and return the absolute target pathname.
- **`(copy-file source target &key (if-exists :error) (synchronize nil) (follow-symlinks t))`** — Stream a
  binary copy of `source` into an atomic target, then return the absolute target
  pathname. `if-exists` is `:error` (the default) or `:supersede`; only the
  latter replaces an existing target. The `:error` check cannot atomically
  exclude a concurrent target creator. Source size does not determine heap use.
  The resolved source must be a regular file; FIFOs, sockets, and device entries
  are rejected before they are opened.
  When `follow-symlinks` is true, an existing target that denotes the same file
  as `source`, including a hard or symbolic link, is rejected even with
  `:supersede`.
  A newly created target retains the source mode plus access and modification
  times; an existing regular target retains its access permission bits when
  superseded. With `follow-symlinks` false, a symbolic source is recreated as a
  symbolic link with the same raw target text, including broken or relative links.
- **`(copy-directory-tree source target &key (synchronize nil))`** — Copy a real
  source directory, including empty directories and symbolic links without
  following them, into an initially absent target directory. Regular files are
  staged through atomic replacements; modes, access times, and modification
  times are retained for regular files and directories. The completed tree is
  published by a same-parent rename. `target` cannot be `source`, a lexical
  descendant, or resolve through a symbolic-link parent into `source`; callers
  must prevent a concurrent creator of `target`.
  Special filesystem entries such as FIFOs and sockets are rejected. With
  `synchronize` true, staged directories and the target parent are `fsync`ed.
- **`(copy-path source target &key (synchronize nil))`** — Copy one filesystem
  entry to an initially absent target, selecting `copy-file` for regular files
  and symbolic links and `copy-directory-tree` for real directories. Links are
  preserved without following them, including relative and broken links.
  FIFOs, sockets, and device entries are rejected. `synchronize` is passed to
  the selected copy operation.
- **`(call-with-advisory-file-lock thunk stream &key (wait t) timeout (mode :exclusive))`** —
  Acquire a cooperative lock from `stream`'s current byte position through
  EOF, call `thunk` with `stream`, then release the lock on every exit path.
  `mode` is `:exclusive` by default; `:shared` locks coexist with other shared
  locks, while an exclusive lock conflicts with either mode.
  `stream` must be an open SBCL file-descriptor stream. With `wait` false, a
  conflicting lock signals `host-operation-failed` instead of waiting. This
  is an advisory lock: other processes must use compatible locking for it to
  provide coordination. A non-NIL `timeout` bounds `wait` with a monotonic
  deadline and signals `file-lock-timeout` on expiry. Nested scopes on the same
  stream are reentrant: only the outermost scope releases the POSIX lock.
  POSIX record locks belong to the process, so a nested scope for the same file
  must use that original stream; do not open or close another stream for the
  file while a lock scope is active.
  Repositioning `stream`
  in `thunk` does not change the locked range; the stream retains its final
  callback position after the lock is released.
- **`(with-advisory-file-lock (stream &key (wait t) timeout (mode :exclusive)) &body body)`** — Lexically
  scoped macro form of `call-with-advisory-file-lock`.
- **`(call-with-file-lock thunk pathspec &key (wait t) timeout (mode :exclusive))`** — Opens `pathspec`
  for non-destructive I/O, creating an absent file, acquires the advisory lock from byte zero through EOF,
  calls `thunk` with the open stream, then releases and closes it on every exit path. Options have the same
  semantics as `call-with-advisory-file-lock`. Each call owns a descriptor; for nested locking on the same
  file, use `call-with-advisory-file-lock` with a supplied stream.
- **`(with-file-lock (stream pathspec &key (wait t) timeout (mode :exclusive)) &body body)`** — Lexically
  scoped macro form for `call-with-file-lock`; binds the opened, locked stream in `body` and preserves all
  body values.

## Strings

`src/strings.lisp`

- **`(split-string string &key (separator #\Space))`** — Split `string`
  wherever any character in `separator` (a list of characters, a string, or
  a single character) appears. Consecutive separator characters produce
  empty-string segments between them.
- **`(string-prefix-p prefix string)`** — True when `string` starts with
  `prefix`.
- **`(string-suffix-p suffix string)`** — True when `string` ends with
  `suffix`.
- **`(join-strings strings &key (separator ""))`** — Join a sequence of
  strings with `separator`. An empty sequence produces `""`; every element
  and the separator must be strings, with no implicit object conversion.
