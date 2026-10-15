# Native SQLite custody and lookup snapshots

`Database` remains the original physical connection Owner. Installed callers
must bind it to the original Host, Store, generation, current authority and
managed allocation scope. Neither path equality nor transaction-state DATA
supplies those bindings.

## Fenced reconciliation reads

`Database.prepare_lookup_read` is a narrow extension for a connection already
fenced after an uncertain write. It first establishes physical `NoActive` on
that same connection. An active prior transaction refuses acquisition without
rollback or adoption. There is one nominal read child at a time. A child from
another connection, an old generation, or a retired child cannot authorize a
new read. The generation is private Owner material, not a wire-issued grant.

The original Database retains the child before read start. It permanently sets
and verifies SQLite `query_only`, executes `BEGIN` once and actually reads the
database to pin its snapshot before issuing `ReadyLookupRead`. The closed child
API exposes bounded row/scan, header, capacity and usage observations. It exposes
no mutation or arbitrary SQL. Normal transaction/mutation operations and parent
close refuse while this child remains outstanding. Existing installed fenced-
active read guards must remain unchanged; only the exact child's port can admit
its active read. Low-level unfenced/private-row diagnostic APIs do not establish
committed inventory or installed authority.

Every child read checks the original physical connection/context before and
after observation. `finish` requires readiness and current, confirms only that
child's physical stop, then checks current again. Its success completes a read
observation, never the earlier write's COMMIT, Store/Run outcome, capacity release
or replay permission. Callers must retain their complete-observation publication
until this stop and their own Host/Store current checks have succeeded.

`PendingLookupRead` retains the same child after partial start or a lost response.
`retry_cleanup` drains/inspects that exact start/stop attempt: it never repeats
BEGIN or blindly reissues a lost stop. A known pre-SQL stop refusal can retry
cleanup; an uncertain stop which still reports active retains the original debt.
A lost stop with confirmed physical NoActive can retire the child without sending
another rollback. Cleanup ACK never repairs a failed observation. The original
fence is monotonic, query_only is not reset, and the original unconfirmed write
identity remains with its existing caller. Close cannot silently discard a live
or pending child. Failed current/cleanup retains original custody and does not
permit another connection or fresh borrow to replace it.

Unsupported targets refuse before acquisition. Selected-component current,
Library/domain lifetime, actual allocation funding and the installed caller's
Store/authority checks remain separate requirements; this API does not supply a
normal numerical profile or a complete Python Local assembly.
