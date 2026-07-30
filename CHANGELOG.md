# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.1.0]

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
- The first release defines a deliberately narrow, documented subset of
  UIOP-shaped pathname, filesystem, environment, and string operations.
  Process launching and UIOP's broader keyword-argument surface are out of
  scope.
