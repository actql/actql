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
Local and DuckDB task completions share an opaque output boundary. DuckDB start
retains the exact attempt and blocks further task starts until verified completion.
The standard Node Host supplies its transport verifier and records success through
that same owned attempt; unrelated completed outputs are not accepted. Revocation
of in-flight material is separate from native DB-stop acknowledgement.
The run owns one immutable ledger reference. Standard Node DuckDB task starts
reserve their transfer ceiling and configured DB memory before creating resources.
The transport charges the same physical frames to the local session ceiling and
the run ledger, before send/accept. Only confirmed native cleanup releases unused
transfer and DB-memory reservations; failure never refunds consumed transfer.
Task configuration cannot substitute a fresh ledger for a running graph.

Retained-buffer and adapter-scratch accounting, Local
physical enforcement described below must
be connected before this is presented as
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

The Node session keeps the primary execution failure separately from cleanup
errors. If an owned connection/instance cannot be closed, the error retains a
live `cleanupHandle` with status and serialized cleanup retry. That handle owns
the same remaining resources and settlement callback; it cannot run Compute or
turn failure into success. Cleanup acknowledgement follows actual resource
closure, not merely a cancellation request. A rollback error followed by confirmed
connection/instance closure is still a cleanup error, but not pending capacity.

A bounded cancellation-wait policy may return failure while the original session
still owns resources. Its live cleanup handle continues observing that exact
operation; no second execution is created. Pending capacity remains reserved until
the original session confirms cleanup. Status inspection is nonblocking; cleanup
retry may await native settlement and never turns the cancelled task into success.
The wait deadline is not a native process-kill deadline or a durable recovery claim.

## Comparison and revision

The bounded search enumerates combinations of Host-owned conditional task offers.
Each offer belongs to one execution and an exact capability registration; equal
registration names or equal input content do not substitute for ownership. These
future-input estimates are not completed inputs or proof of provider applicability.
Before starting, the selected registration must still produce an eligible candidate
bound to the task's exact completed `ProducerRead` through existing admission.

Search bounds offer count, combination count, traversal work and revision count.
Offer construction and enumeration charge the execution's planning ledger before
work. Reports retain infeasible combinations and their resource rejection, not
only the winner. Transfer envelopes add per actual task; retention is conservatively
summed without assuming future release or sharing; serial execution memory takes
the maximum envelope. Existing consumption, holdings and pending reservations
reduce available capacity. The Node start also checks its requested transfer and
DB-memory ceilings against the selected envelope before reserving resources.

Re-evaluation requires a completion generation or physical resource-state change.
Merely spending planning work or submitting different prices does not create new
state. Completed task choices remain in revision history, while comparison totals
cover only unstarted tasks. Unknown estimates defer selection unless an explicit
Host order selects among the feasible combinations; infeasible choices cannot win
through that policy. Deferred or infeasible decisions do not authorize dispatch
using an old selection. Full adapter applicability and retention enforcement must
not be inferred from this conditional comparison API alone.

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
