# Host SQLite failure custody

This change covers the Coordinator, Transfer, and Checkpoint journals. Their
synchronous transactions use one helper, while each journal retains its own
schema, admission, and lifecycle rules. It does not change the Salesforce
adapter, Effect scheduler, or Client request journal.

The result of an operation and the state of its SQLite connection are separate
facts. A failed `COMMIT` has an unknown operation outcome even when a subsequent
rollback leaves the connection outside a transaction. Such a connection may
serve a new operation, but the failed operation must be reconciled from durable
records; Run or Effect work must not be sent again merely because the connection
is reusable. A body failure before `COMMIT` is a known failure when SQLite has
automatically rolled back or an explicit rollback has completed.

The helper reads `DatabaseSync.isTransaction` to establish whether a transaction
remains active. It does not infer this from an error string or a successful
query. If state inspection fails or a transaction remains active after failed
rollback, the journal rejects new operations. `close()` remains available and
retryable; reopening the durable journal is the recovery boundary. The thrown
error retains the primary cause, rollback cause, and state-inspection cause as
distinct fields. An unknown operation outcome is never changed to success or
definite rollback by closing or reopening the connection.

Regression evidence uses real SQLite for `RAISE(ROLLBACK)` automatic rollback
and deferred foreign-key failure at `COMMIT`. A fault-injected rollback after
the real failed `COMMIT` checks compound causes and the new-operation fence.
The Coordinator journal's physical close is fault-injected once and succeeds
on retry, after which the same durable file reopens. The existing three journal
test suites continue to exercise their records and state transitions.

The earlier D CI failure at `resumed.close()` in the reference Site recovery
case is not yet attributed to a specific owner. This branch adds one-time
diagnostics for pending shutdown owners and individual cleanup causes. The
targeted recovery test succeeded locally, so this change does not add a blind
retry or claim the CI failure is fixed. A recurrence should be diagnosed using
those fields before changing the cleanup protocol.
