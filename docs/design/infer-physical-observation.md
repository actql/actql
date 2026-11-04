# INFER physical diagnostic boundaries

The existing Model execution Owner retains the original durable Entry and
its issued one-shot gate across the `BeforeInvoke` diagnostic callback. That
callback is explicitly **unsent**. Cancellation, deadline, current dispatch
authority, egress and the original reservation are checked again after it.
Only then is the original gate consumed and the fixed invocation entered.
No diagnostic callback, await or request reconstruction occurs between final
consumption and invocation.

`InvokeStarted` reports that the installed invocation entry was crossed. It
does not prove network transmission, provider acceptance, response validity,
capture persistence or Run success. The synchronous interface delivers this
fact after the invocation returns; the subsequent return/failure/cancellation
fact describes that invocation's disposition only. An invocation that throws
or loses its response can leave the already retained durable Entry unresolved;
absence of a start diagnostic does not prove that no send happened. It grants
neither a new gate nor an automatic retry.

Diagnostic delivery timestamps cannot measure the synchronous invocation's
duration. The Node observation consumer therefore omits duration for these
facts. A conforming asynchronous physical adapter may separately measure its
actual boundaries; a missing measurement remains unknown, not zero. The
pre-gate diagnostic is not exported as a completed transport observation.

Both immediate and polled persistence use the same original final gate.
Saved acknowledgement custody is independent of current send permission.
Legacy non-durable calls also recheck their existing current authorities after
the diagnostic callback. No new Run, Ledger, approval or execution Owner is
introduced by these diagnostic boundaries.

## Complete Model groups on one Request

A Pure computation with several checked INFER occurrences retains their full
compiler order through one TaskCompilation, module and Model Plan. Source-free
and captured modules use the same aggregate Plan fold. Compute demand is read
once from the selected module; each actual Model and read partition contributes
once. A Source capture retains the original checked Direct Stage/input/task
coordinates from preparation through acquisition and execution. Occurrence order
is not a substitute for Stage or input coordinates.

The existing original read owns a closed group of consumers on one Run binding,
one descriptor, one read claim and the same Ledger. Each original Model Scope
consumes only its declared partition. Work and attempts remain consumed when a
child retires. A refused first admission cannot obtain a replacement claim or
snapshot. The native fixed group records and actual child arrays use the common
representation units; small Host control frames use the existing common control
envelope, independently of JS closure or wrapper spelling.

The first completed original Model retains the one complete publication borrow.
Later Model captures use that same original borrow without changing compiler
order. Observation issuance validates the complete original group. Every child
publication alias and Store duty retires before that borrow returns; every
actual read and Scope retires before the existing Run and Request aliases are
severed. Construction failure and cancellation use this same cleanup sequence.
A pending child, reentry or replaced carrier cannot become parent cleanup ACK.

A complete group is not a singular Model-state writer. The existing singular
writer refuses a group before consuming its descriptor. Authenticated recovery
and independent saved Result access retain their existing contracts; a fresh
Scope or successful public status is not a physical-stop or recovery receipt.
