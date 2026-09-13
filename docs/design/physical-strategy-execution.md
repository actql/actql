# Serial physical strategy execution

## Scope and semantic ownership

A physical strategy realizes existing checked units; it is not a canonical Plan,
Program success, Run admission, or permission to publish Results. Data edges are
owned producer/target/receiver ports. Control edges come from checked incoming
success gates, not from reachability in the data graph. Both must be satisfied.
Splitting work does not create independent semantic success boundaries.

The initial execution profile is finite, serial, single-input Relation
filter/select. Its acceptance graph shares one completed acquisition X between
A and B, with C reading A. All Stage activation barriers remain mandatory even
when B has no data dependency on A. A task failure prevents further starts;
successful independently completed computations are not retroactively revoked.
Internal success records are not partial successful Program publication.

`CapturedInputSource` encapsulates an already captured mock, broad or native
observation. It exposes binding and live metadata, not a raw pre-capture output.
Its bindings compose the original output's live condition with the exact
issuer/attempt/observation check. `CapturedDAG` checks that this source belongs
to the same checked Program and bound acquisition as its root. Completed local
tasks are recorded only by invoking the selected existing Compute implementation;
callers cannot inject arbitrary completed outputs as task success. A candidate
must refer to the exact ProducerRead prepared for that task, not equal rows.

The captured-input serial runner is an incremental internal implementation.
Its Local task path does not yet provide the integrated DuckDB execution,
whole-strategy comparison, physical-ledger enforcement or asynchronous cleanup
described below. Those mechanisms must be connected before it is presented as
the complete physical strategy Host. Checked topology validation alone is not
validation of all runtime Stage obligations or a Program success issuer.

## Transfer and execution ownership

Local fixed inputs and DuckDB's per-Compute temporary database use completed
input handoff. Import, SQL, result receipt and cleanup belong to one frozen
Compute attempt. Transfers have explicit source/destination ports, representation,
accounting and enforcement, but are not independently reusable DB capabilities.
A DuckDB A-to-C edge exports A and imports it into C's new database. No resident
table reuse, cross-task streaming, or unimplemented sharing discount is assumed.

External captures are borrowed. An execution must not close its caller's capture.
Internal acquisition/Compute resources are execution-owned and released after
their last required use. Required checked outputs and explicit held result ports
extend retention. Buffer retention is distinct from table-handle lifetime; sharing
requires the exact owned allocation, not equality of its contents or CID.
Upstream revocation prevents new consumers but does not invalidate a consumer
which already established its independent completion. No public lease is added.

## Physical accounting

The Host ledger is separate from every selected logical guard and fragment
budget. Its limits are not evidence of semantic conformance. Reservation and
charges precede the corresponding allocation, transfer or acceptance. Estimates
never discharge a reservation or a logical limit.

| Quantity | Unit and subject | Enforcement and release |
| --- | --- | --- |
| Planning work | bounded graph/candidate traversal and re-evaluation entries | charged before traversal; never refunded |
| Transfer | UTF-8 bytes of selected physical parameter/result transport frames, including their serialized framing; not logical value bytes or DB-page traffic | reserved before the attempt and charged before each send/accept; consumed bytes never refunded |
| Retention envelope | Host-reserved byte capacity of an owned retained allocation, including its adapter-declared container allowance | reserved before allocation; transferred to an exact holding token; released only when that allocation is no longer needed |
| Execution memory envelope | configured per-attempt backend memory capacity and adapter scratch allowance | reserved before resource creation; released only after stop/cleanup confirmation; not reported as measured RSS |
| Attempt/holding entries | opaque reservation and allocation records | bounded before record allocation; no unbounded history or token creation |

Two copies with the same CID have distinct holding tokens. Multiple references
to the same physical allocation share one token only through the owning Host.
Releasing a view does not release the token while a retained result still needs
its backing allocation. Transfer reservation settlement moves the same usage
from reserved to consumed rather than counting it twice. Retention is budgeted
conservatively by owned capacity, not described as exact process heap usage.

Cancellation stops new starts but is not confirmation of stopped DB work or
reclaimed buffers. Pending cleanup retains reservations and its original failure.
The same live execution handle can continue cleanup/status inspection. No crash
recovery, durable reservation service, automatic retry or migration is implied.

## Comparison and revision

Compare eligible strategies by serial estimated time, including preparation,
validation, Transfer, computation, capture, retention and cleanup. Bundled work is
not added again as edge costs. Time, transfer and retention are separate units;
unknown estimates remain unknown. Explicit Host ordering resolves unknowns or
ties; without an unknown-selection policy the choice is deferred.

At capture/task completion, new measured input statistics may update unstarted
choices. The first resource creation or input transfer freezes its candidate and
attempt, not the later SQL start. Already consumed work and unsettled reservations
remain on the same ledger across revisions. Compare remaining additional cost
against the same state, not one plan's original total against another's remainder.
Bound revisions and search work; unchanged state does not trigger repeated search.

Node executes trusted adapter operations. Checked graph validation, identity,
meaning, candidate compatibility and logical enforcement remain in MoonBit.
Execution reports distinguish task records, original failure, cleanup failures,
pending responsibility, strategy revisions and Program/publication status.
