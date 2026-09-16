# Provisional selected-index lifecycle

Selected view preparation creates an independent measurement index. Previously,
a consumed selection or failed/cancelled output port could retain that copied
index even though no result receipt could ever own it. Cancelling the value
stream alone did not cover the index: transfer into the stream happens only
after successful verification.

The selected output path now drops the provisional backing array on failed port
installation, failed verification/diagnostic resolution, and cancellation. A
stream cancelled separately is handled when its output port is next cancelled
or finished. This is not an asynchronous notification mechanism for abandoned
ports: the Host must still close owned preparation handles.

Successful issuance instead detaches the port's index reference without clearing
the index transferred to the receipt. Cancelling that consumed port cannot
damage the result. A rejected reentrant finish during the verifier does not
discard metadata still needed by the active finish. The source receipt's index
is independent and is unchanged by these cleanup paths.

Tests retain the failed selection/port handles and inspect the emptied metadata,
check that the source index survives, and check successful receipt reuse after
a late cancellation. This demonstrates removal of the provisional index's
backing-array reference, not synchronous allocator/GC reclamation or a measured
RSS decrease. It does not complete physical metadata byte reservation, handling
of all preparation-object ancestry, or the full managed Run lifecycle. No
resource reservation is reported as returned merely because this cleanup ran.

This change is internal: no public API, normative contract, identity preimage,
capacity ceiling or benchmark acceptance criterion changes.

Verification: execution-relation tests passed 449/449 on each of JS, Wasm and
Native; strict JS checking and all six managed DuckDB/manifest integration tests
passed. Public interfaces match across targets; format and diff checks passed.
