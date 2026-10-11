# Funded original Catalog claim caller

This connects the completed resident consumer to its original funded Journal
acceptance. It does not infer initial eligibility from a missing credential use,
an absent Checkpoint, or the consumer's informational pending-duty boolean.

The consumer selects only its own nominal custody. It checks its completed
Effect computation, the original producer runtime/dispatch, the producer's
actual capture context and CapturedDAG Ledger, and the exact consumer dispatch.
The Journal checks the same physical Journal, confirmed acceptance, open
original reservation, no cleanup in progress, current Site admission,
uncancelled original request, and the original unclaimed row at revision zero.
The read is non-mutating. Claim delegates to the existing transaction, which
rechecks original admission/cancellation and atomically consumes revision zero.
No caller-supplied dispatch replaces the request held by nominal custody.

## Resource integration order

1. Original consumer acceptance establishes the funded custody in the real
   accept transaction. A failed save retains that same reservation for retry.
2. The actual completed consumer supplies `read_initial_catalog_use` for
   preparation. This is neither a send grant nor a successful claim.
3. The existing Resource initial-use hook calls the consumer's
   `claim_initial_catalog_use` after current Host/credential authorization.
4. The Resource Owner selects and persists its original ordinal/nominal use.
   Its post-save hook retains that use through the same Journal and original
   claim before the existing final current/lifetime/revocation/send fences.
5. Once a claim has been consumed, missing use/response/DB state remains an
   unresolved original responsibility. Repeated readiness/claim calls cannot
   turn it into another GET. Saved-use restoration remains the separate path
   adopted in #1531.
6. Existing consumer/Resource/Review cleanup and the original producer Ledger
   remain the owners of custody and release. Read/claim does not settle capacity.

## Scope

This is the nominal caller API boundary, dependent on #1513 and its unmerged
Resource/Local preparation ancestors. Its final merge target is main after those
parents. It does not install production funding coefficients, wire the CLI
Resource hook, restore nominal custody across a process restart, grant Host
access, or complete public Effect approval/execution/Result/release.

The five new actual-SQLite fixture cases cover non-mutating reads/one claim,
foreign Journal with equal dispatch bytes, save rollback followed by the same
funded acceptance, claim-reply loss/missing original row, and cancellation/Site
generation change. Matching Native
compile and execution evidence must be reported separately. No Provider call is
part of these cases.
