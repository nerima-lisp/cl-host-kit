# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Initial release: `getenv`/`(setf getenv)`, `quit`, `getcwd`, `chdir`,
  `absolute-pathname-p`, `directory-pathname-p`, `ensure-pathname`,
  `ensure-directory-pathname`, `ensure-absolute-pathname`,
  `pathname-directory-pathname`, `truenamize`, `file-exists-p`,
  `directory-exists-p`, `directory-files`, `subdirectories`,
  `delete-directory-tree`, `rename-file-overwriting-target`,
  `temporary-directory`, `read-file-string`, `split-string`, and
  `string-prefix-p`. Every OS-facing call is built on SBCL's `sb-posix`
  contrib or plain Lisp file operations; there is no dependency on `uiop`
  or any other external library.
- The scope of this first release is the exact union of `uiop:` symbols
  nerima-lisp's own production code calls (excluding process launching,
  which is `cl-process-kit`'s domain), each implemented against the
  narrower argument contract those call sites actually use rather than
  uiop's full keyword-argument surface.
