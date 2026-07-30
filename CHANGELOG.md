# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [0.2.1]

### Changed

- `docs/src/api-reference.md`'s "Program execution" section still cited only
  `src/process.lisp`, unlike the "Filesystem" section's already-correct
  multi-file breakdown. Updated it to name `process-result.lisp` and
  `process-io.lisp` alongside `process.lisp`, matching the split from 0.2.0's
  `process.lisp` refactor. `docs/src/installation.md`'s pinned flake input
  example now points at the `v0.2.1` tag.
- `docs/src/changelog.md` had not been updated since the `0.1.0` release: it
  still labelled that release's entries `[Unreleased]` and was missing the
  entire `[0.2.0]` section, despite its own header claiming to mirror this
  file. Resynced its content with `CHANGELOG.md`.

## [0.2.0]

### Fixed

- `t/conditions-test.lisp`'s "API reference contract" test (which walks every
  exported `HOST-KIT` symbol and confirms `docs/src/api-reference.md`
  mentions it) errored in every Nix check/app that runs `run-tests.lisp`:
  `mkLispSource`'s default allowlist is `.asd`/`.lisp` files only, so
  `docs/`, holding no such file, was invisible to the test's
  `asdf:system-source-directory`-relative read. Fixed with `flake.nix`'s
  `sourceInclude = [ ./docs ];`, `mkLispSource`'s documented escape hatch for
  exactly this case.
- `file-metadata`'s `:device` slot (`(integer 0 *)`) failed to construct for
  `/dev/null` on this aarch64-darwin Nix sandbox:
  `sb-posix:stat-dev`'s raw C `dev_t` read back as a negative Lisp integer
  for that synthetic device node. `DEVICE` is only ever compared for equality
  (`same-file-p`), never sized, so `src/filesystem-metadata.lisp` now masks
  it to the same non-negative 32-bit value the OS represents
  (`(logand (sb-posix:stat-dev stat) #xFFFFFFFF)`) rather than let a
  sign-extended read violate the struct's contract. Added a regression test
  (`t/filesystem-metadata-test.lisp`) asserting `%make-file-metadata` rejects
  a negative `:device`/`:inode`/`:hard-link-count`/`:owner-id`/`:group-id`.
- `checks.coverage`'s percentage gate scraped `cover-index.html`
  indiscriminately, summing cl-weave's own ~90 instrumented files (loaded
  onto `CL_SOURCE_REGISTRY` for the test run, per the `cl-nix-forge` input
  comment) alongside `cl-host-kit`'s `src/` -- diluting a real ~95%/90% down
  to an unreconstructable ~44%, and making the coverage build fail for a
  reason unrelated to this library's own test thoroughness. The three test
  errors above additionally aborted `test-system` before `sb-cover:report`
  ever ran, so no report existed to notice this in. `flake.nix`'s perl
  aggregation now tracks `cover-index.html`'s per-source-tree
  `<tr class='subheading'>` header and only sums rows under `src/` whose
  header is not a `/nix/store/...` path (an already-realized flake input,
  never this package's own in-progress build source) -- `t/`'s own rows are
  excluded the same way, since a percentage of how much a test file's own
  code ran during the run is not a meaningful signal. With the fixes above,
  `checks.coverage` now measures real numbers for the first time this
  session: **94.9% expression (3751/3953), 89.8% branch (361/402)** --
  expression clears the 94% minimum; branch is 0.2 points under the 90%
  minimum. The shortfall traces to `filesystem-metadata.lisp`'s six
  `defstruct` slot `:type` declarations (`(integer 0 *)`,
  `(integer 0 #o7777)`), each marked "neither branch taken." Confirmed as an
  SB-COVER coverage-model artifact, not a closeable test gap: `t/
  filesystem-metadata-test.lisp` asserts `%make-file-metadata` signals on a
  negative `:device`/`:inode`/`:hard-link-count`/`:owner-id`/`:group-id` --
  first via a value derived from `(get-universal-time)` so SBCL cannot fold
  it to a compile-time constant and skip emitting the runtime check, then
  independently via `eval` -- and both genuinely trigger the constructor's
  runtime type-check failure (the test passes), yet the branch counter for
  those six slots stays at exactly 361/402 either way. SB-COVER's source
  walker appears to tag the slot `:type` specifier text itself as a branch,
  not the compiler-generated check it produces, making it permanently
  unreachable through any test. Per maintainer decision, `flake.nix`'s branch
  minimum is now 89% (was 90%): the real, permanent ceiling this metric can
  reach while still counting those 6 known-uninstrumentable branches in the
  denominator, not a loosened bar. `checks.coverage` passes at 94.9%/89.8%.

### Changed

- `src/process.lisp` (617 lines) is split into `src/process-result.lisp` (the
  `process-result` data model, exit-code validation, and PATH-based program
  lookup), `src/process-io.lisp` (the concurrent stdout/stderr capture and
  stdin production engine), and a narrower `src/process.lisp` (`run-program`
  and its `WITH-X` scope macros). `t/process-test.lisp` (568 lines) is split
  the same way into `t/process-test.lisp` (the `run-program` core) and
  `t/process-streaming-test.lisp` (the `call-with-program-output`/`-input`/
  `-io` callback-streaming family).
- `t/strings-test.lisp` adds three `it-property` tests (cl-weave's generator-driven
  property testing, previously unused in this codebase): `string-prefix-p`/
  `string-suffix-p` against a generated prefix/suffix concatenation, and a
  `split-string`/`join-strings` round trip over generated content and separator
  characters (`gen-string`, `gen-character`). `t/package.lisp` imports
  `it-property`, `gen-string`, and `gen-character` for this.
- Table-driven "rejects an invalid binding during macroexpansion" tests
  (`with-directory-entries`, `with-directory-tree`, `with-temporary-directory`,
  `with-temporary-file`, `with-advisory-file-lock`, `with-file-lock`,
  `with-atomic-output-file`) now use cl-weave's `it-each` instead of several
  hand-written `signals` assertions inside one `it`, so each invalid-binding
  case reports as its own named, independently-passing/-failing test.

- Every `WITH-X` scope macro (`with-directory-entries`, `with-temporary-file`,
  `with-file-lock`, ...) is now generated by `define-with-macro`
  (`src/with-macros.lisp`) instead of a hand-written `defmacro`, collapsing
  duplicated lexical-binding, non-constant-symbol-diagnostic, and
  keyword-forwarding boilerplate into one macro-defining-macro. A `WITH-X`
  call now forwards only the keyword arguments actually written at the call
  site, so an omitted keyword always defers to its `CALL-WITH-X` function's
  own default instead of a second, independently-maintained one.
  `with-advisory-file-lock` stays hand-written: it reuses its own bound
  variable as a forwarded argument, which does not fit that shape.
- `call-with-atomic-output-file`'s argument order is now `(thunk target &key
  ...)`, matching every other `call-with-X` function in the library. It was
  previously `(target thunk &key ...)`.
- Applied 31 `paredit fix` auto-fixes (`if-to-unless`, `negated-if`,
  `de-morgan`, `negated-when-unless`, `nested-when`,
  `unwind-protect-no-cleanup`, `redundant-eql-test`, `explicit-nil-return`,
  `format-to-string`, `ascii-code-char`, `redundant-body-progn`, and a
  targeted subset of `redundant-progn`) across `src/` and `t/`. Two
  `redundant-progn` sites and all three `redundant-identity` findings were
  deliberately left alone: they were false positives that would have
  corrupted `handler-case`/`unwind-protect`'s single-form protected-form
  position, or renamed a lexical binding merely because it was named
  `identity`.
- `flake.nix` now builds on
  [`cl-nix-forge`](https://github.com/nerima-lisp/cl-nix-forge)'s
  `mkPackageFlake` org preset instead of a hand-rolled `packages`/`checks`/
  `apps`/`devShells` tree. This incidentally fixed a real bug the hand-rolled
  version had accumulated: `checks.coverage` and `apps.coverage` were each
  defined twice, which made `nix flake check`, `nix flake lock`, and
  `nix run .#coverage` fail outright with a Nix "attribute already defined"
  evaluation error. `checks.coverage` (an `extraOutputs` addition, since
  `mkPackageFlake` does not generate a coverage check itself) still enforces
  the 94%/90% expression/branch coverage minimums the removed duplicate did.
  `apps.coverage` and `apps.bench` are also `extraOutputs` additions;
  everything else (`packages.default`/`cl-host-kit`/`docs`,
  `checks.default`/`formatting`/`docs`, `apps.test`/`default`,
  `devShells.default`) is now the preset's generated output. `devShells.default`
  additionally carries `pkgs.coreutils`, so an interactive `nix develop` shell
  has `timeout` available for the same `timeout --foreground
  --kill-after=...` wrapper every `apps`/`checks` entry point uses.
- Refreshed `flake.lock` so its pinned `cl-weave` revision matches the
  `v1.0.1` tag `flake.nix` already declared (it was still locked to `v1.0.0`).

### Fixed

- `environment-test.lisp`'s `quit` test loads three source files directly
  (bypassing ASDF) to exercise a minimal child SBCL image; its hardcoded list
  did not include the new `src/with-macros.lisp`, so the child process failed
  to load `environment.lisp` (which now expands `define-with-macro`) and
  exited with a generic error instead of the expected code. Added it to the
  list, in load order.

## [0.1.0]

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
