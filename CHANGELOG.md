# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Initial release: `getenv`/`(setf getenv)`, `quit`, `getcwd`, `chdir`,
  `absolute-pathname-p`, `directory-pathname-p`, `ensure-pathname`,
  `ensure-directory-pathname`, `ensure-absolute-pathname`,
  `pathname-directory-pathname`, `parent-directory-pathname`, `truenamize`,
  `pathname-within-p`,
  `file-exists-p`, `directory-exists-p`, `file-executable-p`,
  `directory-files`, `subdirectories`, `call-with-directory-entries`,
  `call-with-directory-tree`, `ensure-directory-tree`,
  `delete-file-if-exists`, `delete-empty-directory`,
  `delete-directory-tree`, `move-path`,
  `temporary-directory`, `read-file-string`, `read-file-lines`,
  `read-file-octets`, `split-string`, and `string-prefix-p`. Every OS-facing
  call is built on SBCL's `sb-posix` contrib or plain Lisp file operations;
  there is no dependency on `uiop` or any other external library.
- Filesystem metadata and symbolic-link inspection through `file-metadata`,
  `symbolic-link-p`, and `read-symbolic-link`. Metadata explicitly controls
  whether links are followed, so broken links can be inspected safely.
- Filesystem mutation through `create-symbolic-link`, `create-hard-link`,
  `set-file-mode`, and `set-file-times`, with timestamp values represented as
  Common Lisp universal times.
- Scoped temporary directories and files, including guaranteed cleanup on
  non-local exits, retained resources on successful completion, binary and
  text streams, requested filename suffixes, and optional durable writes.
- Atomic text and octet replacement plus binary `copy-file` with an explicit
  no-replace default, opt-in replacement, and optional `fsync` durability,
  alongside scoped advisory file locking with bounded waits.
- Staged directory-tree copying that preserves regular files, empty directories,
  symbolic links, modes, and second-resolution access/modification times while
  rejecting unsupported special filesystem entries.
- Direct, shell-free program execution with executable discovery, environment
  and working-directory control, bounded concurrent output capture, timeout
  cleanup, and explicit non-zero-exit handling.
- Process-environment snapshots and dynamic environment bindings, command-line
  argument and hostname access, and dynamically scoped working directories.
- Atomic multi-variable environment scopes with preflight validation, duplicate
  detection, reverse restoration, and serialized HOST-KIT environment writes.
- The scope of this first release is the exact union of `uiop:` symbols
  nerima-lisp's own production code calls, each implemented against the
  narrower argument contract those call sites actually use rather than
  uiop's full keyword-argument surface.
