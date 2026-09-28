# Initialization and cleanup ownership

This change closes three remaining initialization boundaries on the 0.1
standard Host. It does not add a new scheduler, retry policy, or SQLite
framework.

- The credential journal uses the same transaction helper as the other
  journals. A failed COMMIT remains an unknown operation outcome even if the
  connection can be reused. Primary, rollback, and state-inspection failures
  remain separate. An uncertain operation is never retried automatically.
- The first credential-journal `close()` fences new operations. Database
  release and directory synchronization have separate completion flags. If
  synchronization fails after the database closes, a subsequent `close()`
  retries only synchronization; an unfinished Site retains its cleanup owner.
- An installed Host creates its diagnostic observer inside the initialization
  cleanup boundary. Invalid observer configuration cannot orphan an acquired
  Source or Effect. Diagnostic delivery remains best-effort; ownership cleanup
  does not.
- Coordinator, Transfer, Checkpoint, and credential journals protect statement
  preparation after schema initialization. A constructor failure closes once,
  or returns the original failure with a retryable cleanup handle if close
  fails. The schema and post-schema handlers do not wrap each other.

Regression evidence uses real SQLite connections and an installed Site:
post-schema prepare failure with successful and failed close for all four
journals; credential COMMIT uncertainty; database close followed by a real
directory permission/sync failure and sync-only retry; Site close retry and
new-operation rejection; and an installed Source whose cleanup fails after
invalid diagnostic configuration. The upper Host failure retains the primary
cause, cleanup cause, and retry handle.

Effect indexing and Local resource-checker restructuring are separate P3
work. No Run or Effect replay was added here.
