# v0.4.0 release notes draft

Applications can retain an exclusive advisory file lock across operations with
`try-acquire-file-lock`, inspect its metadata stream with `file-lock-stream`,
and release it with `release-file-lock`. `file-lock-held-by-other-process-p`
queries whether another process holds a conflicting lock without retaining one.
Local queries and rejected duplicate acquisitions preserve the registered lock.
Scoped acquisition of a locally retained lock is rejected before opening another
descriptor. The library keeps the owned stream alive until explicit release.
Release flushes metadata before unlocking and closing the stream, leaving the
lock file on disk. If I/O fails, release still attempts cleanup and reports the
first error to the caller.

Pathname-scoped locks retain their waiting behavior for another thread's
scoped reservation: `wait` true waits before opening a descriptor, with one
deadline across local and other-process lock contention. `wait` false rejects
the request immediately, and timeout expiry signals `file-lock-timeout`.
Retained reservations and same-thread pathname nesting are rejected immediately.
If a shared borrower outlives the opening callback, output handling and owned
descriptor closure wait for the final local owner. Normal completion of the
opening callback flushes pending output before unlocking; abnormal completion
discards it when the stream closes. Cleanup failures do not replace an error or
nonlocal exit already unwinding from a callback.

Pathname-based shared scopes in different threads are now serialized instead of
coexisting, so `wait nil` requests that could previously succeed now signal
`host-operation-failed`, because closing any descriptor for the inode releases
the process's POSIX record locks.

POSIX locks remain process-owned. Callers must not open or close another stream
for the same inode while a lock is held. Locks are advisory, and reliable
coordination on NFS is not guaranteed. Registry and owned-descriptor operations
use a process-wide mutex, so blocking `stat`, `open`, flush, or close calls on
NFS or FIFOs can delay unrelated kit lock operations. Lock timeouts do not bound
those filesystem calls.

Atomic output and whole-file writers accept `mode` for newly created targets.
Permissions are applied through the temporary file descriptor before rename.
Existing targets retain their access permission bits. Omitting `mode` retains
the temporary file's `#o600` permissions.

Atomic output, whole-file writers, and `copy-file` accept a temporary basename
`prefix`. Regular-file staging still defaults to `.host-kit-`. Symbolic-link
copies retain `.host-kit-copy-` when the option is omitted. Copying continues to
preserve source metadata for new targets and existing target access bits when
replacing a regular file.

Directory enumeration, `ensure-directory-pathname`, and temporary-resource APIs
now preserve literal native filename components as nonwild pathnames. Their
`namestring` representation may contain CL escapes, including a backslash before
`[`. Use `sb-ext:native-namestring` for native filename display, comparisons, and
external program arguments rather than passing those CL escapes to the OS.

Filesystem path arguments to APIs such as `file-metadata`, `delete-path`,
`write-file-string`, and `try-acquire-file-lock` interpret strings as CL
namestrings and reject them if they parse as wild pathnames. Use
`sb-ext:parse-native-namestring` to construct a pathname for literal wildcard
characters. Raw symbolic-link target strings continue to be stored verbatim.
