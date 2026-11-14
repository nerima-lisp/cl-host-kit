# v0.4.0 release notes draft

Applications can retain an exclusive advisory file lock across operations with
`try-acquire-file-lock`, inspect its metadata stream with `file-lock-stream`,
and release it with `release-file-lock`. `file-lock-held-by-other-process-p`
queries whether another process holds a conflicting lock without retaining one.
Local queries and rejected duplicate acquisitions preserve the registered lock.
Release flushes metadata before unlocking and retires the reservation even if
I/O fails, reporting the first error to the caller.

POSIX locks remain process-owned. Callers must not open or close another stream
for the same inode while a lock is held. Locks are advisory, and reliable
coordination on NFS is not guaranteed.

Atomic output and whole-file writers accept `mode` for newly created targets.
Permissions are applied through the temporary file descriptor before rename.
Existing targets retain their access permission bits. Omitting `mode` retains
the temporary file's `#o600` permissions.

Atomic output, whole-file writers, and `copy-file` accept a temporary basename
`prefix`. Regular-file staging still defaults to `.host-kit-`. Symbolic-link
copies retain `.host-kit-copy-` when the option is omitted. Copying continues to
preserve source metadata for new targets and existing target access bits when
replacing a regular file.
