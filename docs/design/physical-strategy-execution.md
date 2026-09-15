# Serial physical strategy execution

## Scope and semantic ownership

A physical strategy realizes existing checked units; it is not a canonical Plan,
Program success, Run admission, or permission to publish Results. Data edges are
owned producer/target/receiver ports. Control edges come from checked incoming
success gates, not from reachability in the data graph. Both must be satisfied.
Splitting work does not create independent semantic success boundaries.

The execution profile is finite and serial. Each Compute is either
filter/select, an explicit equikey inner join, or one group with row count/direct-field non-NULL count; aggregate
expressions, aggregate filters and distinct counts remain unsupported. Its
acceptance graph shares one completed acquisition X between
A and B, with C reading A. All Stage activation barriers remain mandatory even
when B has no data dependency on A. A task failure prevents further starts;
successful independently completed computations are not retroactively revoked.
Internal success records are not partial successful Program publication.

Each Compute exposes its exact final checked port: step 1 for filter/select,
step 0 for a single group or inner join. Local and fresh-import DuckDB dispatch
bind every ordered input port, including two references to the same producer.
Native static eligibility compiles all input schemas before cost comparison;
runtime preparation binds live inputs and the bounded null/cardinality preflight
configuration. The actual checks run once at Compute admission, after common
input guards and before native work. Their explicit work/scratch allowance is
charged to planning during dispatch preparation; an input guard failure does
not refund that allowance. The common native start also requires an output ceiling
no weaker than the checked join claim, before reserving its exact attempt.
A checked edge to an intermediate step is not silently
redirected to the final output. `captured_task_target` supplies this port to Host
diagnostics, completed statistics and resident imports without manufacturing a
completed output. Both local and DuckDB completions obey the same port selection;
acquisition continues to use its separate captured-source binding. Group results
can remain resident for subsequent filter/select or supported join/count tasks,
while independently retained Host results supply admission and completion evidence.
Two-input resident joins bind the exact ordered input set and share only actual
producer tables. This does not provide general aggregation or numeric reductions.

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
reserve their transfer ceiling, configured DB memory and bounded Node transport
representation allowance before creating resources. The allowance uses the same
immutable limits as the executing transport: eight bytes per permitted serialized
UTF-8 transport byte, 256 per cell/column/parameter entry and four per SQL byte.
This declared capacity profile is separate from measured RSS and does not imply
an OS-enforced heap limit or cover independently retained MoonBit outputs.
The transport charges the same physical frames to the local session ceiling and
the run ledger, before send/accept. Only confirmed native cleanup releases unused
transfer and DB-memory reservations; failure never refunds consumed transfer.
Task configuration cannot substitute a fresh ledger for a running graph.

The common asynchronous task lifecycle owns the exact task reservation,
settlement state, provisional holding, successful output installation and final
disposal. Its running handle is not a concrete connector attempt. Private
implementation hooks request cancellation, dispose buffers, confirm reusable
inputs and produce an already verified engine completion; they cannot settle
the common ledger by returning success alone. The common completion boundary
also checks the output's exact bound owner, retained port, fixed-input binding
identities and current liveness.
This port check supplements, rather than replaces, the implementation's exact
input/attempt/transport evidence validation. Cancellation alone never releases
execution reservations. Confirmed execution cleanup may release execution
capacity while keeping completion scratch and provisional output accounted.

The DAG stores only common execution handles, not a parallel array indexed by
concrete backend attempts. The DuckDB bridge retains an opaque task handle that
binds its transport attempt, common execution and provisional resident output.
Ledger and completion operations validate that exact execution against the DAG;
a raw transport attempt cannot be used to recover or replace the binding. Once
disposal and settlement both finish, the common execution detaches its hooks and
the bridge drops provisional resident references. A retained closed handle cannot
reactivate work or release another task's reservation.

The trusted acquisition transport also forwards physical accounting through both
broad and two-receipt native coordinators. Metadata and each actual row receipt
are charged before receiver acceptance. Native session cleanup acknowledgement
precedes synchronous semantic retention and capture; it is not acknowledgement
that captured buffers or later MoonBit working capacity can be released. A caller
cancellation deadline retains the original live cleanup responsibility until that
session actually settles. These hooks belong to trusted Host wiring, not ordinary
Connector registration or Program-supplied callbacks.

The standard `runStrategyNativeHostQuery` entry reserves the same ledger before
opening the source. `configured_native_capacity` includes both retained batches,
the output, three evidence records and the observation, with 256 bytes per
permitted structural entry and eight per permitted text/wire byte. Its separate
scratch allowance includes transport decoding, value/demand measurement and
receipt encoding. These are declared capacity envelopes, not actual heap sizes.
Post-DB scratch remains reserved through capture and retained-root construction.
Only successful completion may transfer the exact holding into `openDAG` once;
that run uses the original ledger. Closing the acquisition then closes root port
zero without erasing descendant holdings or consumed transfer. No raw output
export is exposed by this accounted entry. Borrowed captures and the standalone
broad Host entry do not automatically gain this whole-run accounting.

The standard dispatch supplies integrated explanation. A separate bounded
application example connects public checking and user-supplied documents to
acquisition and dispatch; it is not a general Program frontend. Checked topology
validation alone is not validation of all runtime Stage obligations or a Program
success issuer.

## Transfer and execution ownership

`physical_resources` owns the physical ledger, reservations and holdings without
any connector dependency. Its shared-capacity owner reserves an execution-resource
envelope once; individual retained copies consume suballocations within it.
Borrowing returns an opaque one-use token, so returning one borrower twice cannot
release another borrower's capacity. Retirement rejects new borrowing but releases
nothing; copy cleanup requires all borrower tokens to have been returned, and
resource settlement requires all suballocations to have been released. Read-only
usage snapshots expose capacities and lifecycle facts, not mutable counters or
the owner's reservation. Connector-specific objects remain outside this ledger.

Resident result materialization keeps its physical table name, SQL and storage
construction limits in a connector-owned opaque plan. The shared output lifecycle
retains its allocation, commit state and pending input cleanup, and checks exact
task/input completion before binding the completed storage to that plan. The plan
alone is not completion evidence or authority to publish a reusable copy.

The physical ledger operates without
depending on a planner, driver or concrete connector. These are opaque owned
handles: callers can inspect immutable limits, usage, ownership and availability,
but cannot mutate counters or manufacture a reservation or holding. Settlement
releases unused reservations, not already consumed transfer or independently held
output. Releasing a holding changes its availability, not its owning ledger.
The strategy layer additionally binds those resources to checked tasks and selected
attempts; a ledger handle alone is not execution permission or completion evidence.

`duckdb_host.configure_strategy_dispatch` binds a bounded array of generated
sequences to their exact checked task owners, the owned registry, selected
consumer capacities and transport/execution limits. It copies the configuration
array rather than borrowing mutable caller slots. The next-dispatch operation
recovers the installed preparation entry by exact registration, never by name or
registration position. Local and DuckDB preparation entries retain their own
compiler and binding rules; a lookup is not permission to start or complete work.
DuckDB join preparation keeps physical input names and compiled SQL in an opaque
connector-owned handle. Compilation precedes the Host's preflight-work charge;
binding and bounded input inspection follow that charge. The second phase uses
the handle's exact original request, rather than accepting replacement inputs or
a reconstructed checked owner. A failed input preflight stops the run without
starting native work or falling back to another candidate.
The next-dispatch operation
consults the current whole-strategy revision and checked data/control readiness,
then binds the actual completed input and validates only the selected realization.
Candidate estimates at this binding stage are unknown, not zero; selecting the
sole already-selected realization is not a second cost comparison or fallback.
Each preparation consumes a planning ledger unit and is bounded by its compiler
and candidate limits. A prepared task is single-use; a replaced unstarted
revision invalidates it without creating a DB or starting a Local calculation.

The standard Node `runCapturedStrategy` driver executes that finite serial
sequence through existing Local and trusted DuckDB Host operations. No fixture,
source connection, replacement runtime or verifier callback enters the driver.
It stops on the first failure and preserves that failure, including any live
cleanup handle, alongside internal completed task records. Its result is labeled
Host-task completion/failure, never Program success or partial publication.
Closing the result closes its task ports but not the caller-owned capture.
The driver consumes the current selected revision. An explicitly installed
estimate policy refreshes unstarted choices before the next dispatch preparation;
manual selection remains available without that policy. `explain_captured_strategy` produces bounded
Host-private JSON rather than canonical identity or execution evidence. It keeps
the chosen revision's remaining estimate and ledger-at-selection separate from
current cumulative usage, and preserves disjoint work-slot bundles using copied
arrays. Caller mutation cannot rewrite the explanation after selection. Complete
estimates record `estimated_fastest`; explicit priority with unknown costs records
`host_preferred`. Unknown duration is null and Int64 quantities are decimal strings.
Resource rejection reasons accompany the enumerated alternatives. The report marks
an incomplete search explicitly, including its assessment revision, rather than
presenting a bounded prefix as a completed comparison. Elapsed acquisition time
is not inferred from these remaining-task estimates; already spent acquisition
transfer remains visible in the ledger. Output byte/node limits apply without
changing the run's selection, logical budget or accumulated physical consumption.
Available root statistics reuse the observation's already measured output row
count and canonical row-wire bytes. They do not scan the source again, evaluate
expressions, or identify physical transport frames with canonical value bytes.
Statistics require the original capture to remain available; a closed root
reports no available statistics. A retained estimate may use a recorded statistic
as information, never as renewed input authority or a hard-capacity guarantee.

Local fixed inputs and DuckDB's per-Compute temporary database use completed
input handoff. Import, SQL, result receipt and cleanup belong to one frozen
Compute attempt. Transfers have explicit source/destination ports, representation,
accounting and enforcement, but are not independently reusable DB capabilities.
In the fresh-DB realization, a DuckDB A-to-C edge exports A and imports it into
C's new database. The separate [run-owned resident realization](duckdb-resident-execution.md)
retains exact DB tables for reuse, while preserving Host validation and output
holding. Its shared preparation/import costs and DB reservation are composed
explicitly; neither realization assumes cross-task streaming or CID-based sharing.

External captures are borrowed. An execution must not close its caller's capture.
Internal acquisition/Compute resources are execution-owned and released after
their last required use. Required checked outputs and explicit held result ports
extend retention. Buffer retention is distinct from table-handle lifetime; sharing
requires the exact owned allocation, not equality of its contents or CID.
Upstream revocation prevents new consumers but does not invalidate a consumer
which already established its independent completion. No public lease is added.

The common DAG Compute start, used by the standard Node path, creates a private
reservation before admission or native work. It binds the exact run/task/current
selection, candidate, attempt and concrete limits; no externally created, closed,
foreign-ledger or reused reservation is accepted. The Host supplies the enforced
native execution and serialized-transfer ceilings, not an estimate. Both must be
positive for this protocol. The implementation calculates MoonBit scratch and
retention from its concrete configuration; the common start boundary checks those
capacities, and the initial reservation must fit the selected envelope
and ledger. Later transfer consumption is not confused with initial admission.
The DuckDB implementation derives retention capacity from the exact configured admission limits:
256 bytes per permitted retained value node, physical output row and completion
metadata entry, plus eight per retained text/name UTF-8 byte. These are declared
container allowances, not observed heap size. Native settlement releases transfer
and execution reservations separately; it does not release provisional or completed
result capacity. Successful completion transfers that reservation to an exact
holding token in the same operation that records task success, without a second
charge or an externally visible unheld success. Node forwards charges and cleanup
acknowledgements to this common owner rather than managing a second reservation.
Synchronous preparation runs under that reservation but cannot start external I/O.
It returns private implementation state and lifecycle operations; only the common
driver registers the execution. Preparation rejection releases unused capacity,
without refunding its consumed attempt entry. Once external work can start,
failure instead retains capacity until the corresponding cleanup is confirmed.
Failure disposes provisional material and
settles the remaining reservation only after native cleanup confirmation.

The same immutable Compute configuration supplies a separate MoonBit working
capacity: 256 bytes per permitted transport/physical batch node, cell, row or
column and measurement/depth/completion entry, plus eight per permitted transport,
physical text, measurement and completion-name byte. This bounds the selected
decoding and checking representations; it is not measured allocator usage. It is
added to DB/Node execution capacity before dispatch and remains reserved after
native settlement because demand/output checks still run afterward. Final success
or failed-buffer disposal settles that remainder. Partial settlement may only
reduce a reservation, never increase it or erase pending post-DB responsibility.

Task result ports carry additional revocable liveness without copying or
re-admitting storage. Closing a port removes its output from the run but does not
erase its checked completion record or restart it. Retention dependencies follow
the checked fixed-input edges, including Local descendants which anchor upstream
completion storage. A closed parent's holding remains while a completed child or
in-flight native task needs it. Descendant release or confirmed failed-task cleanup
allows a bounded reverse traversal to release unused ancestor holdings. Task zero
is the exact validated captured root and can receive its Host-owned allocation
token through the same retention operation. Its additional liveness condition
restricts the original observation rather than replacing issuer verification.
Closing root port zero drops the runner's source handle and revokes prepared reads;
completed descendants and pending native cleanup keep its allocation charged.
The runner does not close a borrowed issuer. Acquisition storage not attached to
the ledger remains the caller's responsibility. A trusted Host exporting
an output outside the run must keep its port open for that use; this mechanism
does not discover arbitrary foreign references or promise immediate GC/RSS release.

Local Compute reserves before entering the existing guarded executor too.
`generated_sequence_capacity` derives declared capacities from that exact
generated sequence and its selected limits. Retention allows 256 bytes per
retained/metadata entry and output value node, plus eight per output text byte.
Working capacity allows 256 per operation/metadata/frame/input/output/measurement
node or measurement-depth entry, and eight per input/output/measurement text byte.
The peak serial fragment adds 264 per selected logical live-value byte, 256 per
physical traversal node/depth entry and eight per physical traversal byte. These
are conservative container-capacity allowances, not an assertion that every
potential byte was allocated or that shared payloads were copied. Allocation
tokens and checked ancestry still determine actual sharing responsibility.
Arithmetic overflow or an invalid quantity rejects the capacity description.

Neither deriving capacity nor choosing a different backend changes the selected
logical limits. The reservation must fit both the selected strategy envelope and
the run ledger. A holding record is reserved before Local execution; synchronous
failure releases that attempt's capacity without revoking prior task completions
or refunding cumulative attempts. Success keeps its holding through the same
descendant-aware lifetime mechanism as DuckDB.

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
The standard Host checks static DuckDB eligibility against each exact checked
owner using the adapter's native-expression and import-schema compiler before
generating estimates. Unsupported expressions, import types/shapes and selected
common-fragment contracts exclude that realization independently of price;
`excluded_realizations` records the task, capability and reason. This needs no
future ProducerRead or content CID. It does not replace live input ownership,
resource admission or actual candidate validation at dispatch.
Before starting, the selected registration must still produce an eligible candidate
bound to the task's exact completed `ProducerRead` through existing admission.

Search bounds offer count, combination count, traversal work and revision count.
`max_revisions` bounds accepted search attempts, including unsuccessful or
deferred searches, not only successful selections. Missing tasks, invalid offers
and statically excessive combination counts are rejected by charged preflight;
they can be corrected without fabricated resource progress. An accepted search
immediately revokes the previous dispatch permission. Failure cannot restore it
or repeat the accepted search in an unchanged execution/resource state. Selection
history and spent planning work remain intact.
This includes arithmetic `Overflow` during accepted enumeration. Sending only
corrected cost estimates in the same state does not reopen search or old
dispatch. This rejection is not by itself a stop of the entire Run.
Each remaining Compute needs one attempt and one holding record in this profile;
already consumed records are included in feasibility and revision-state checks,
even if their byte reservations have since been released.
Offer construction and enumeration charge the execution's planning ledger before
work. Reports retain infeasible combinations and their resource rejection, not
only the winner. Transfer envelopes add per actual task; retention is conservatively
summed without assuming future release or sharing; serial execution memory takes
the maximum envelope. Existing consumption, holdings and pending reservations
reduce available capacity. The common start also checks its concrete transfer,
retention and execution capacities against the selected envelope before reserving.

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
The priority array is a full permutation of original enumeration positions,
including infeasible strategies. Charged preflight validates that permutation;
selection removes rejected positions and maps the remaining order to feasible
indices. Reports always retain the original positions, including when all
strategies are infeasible.

At capture/task completion, new measured input statistics may update unstarted
choices. The first resource creation or input transfer freezes its candidate and
attempt, not the later SQL start. Already consumed work and unsettled reservations
remain on the same ledger across revisions. Compare remaining additional cost
against the same state, not one plan's original total against another's remainder.
Bound revisions and search work; unchanged state does not trigger repeated search.

The standard dispatch can install a bounded declarative estimate profile before
its first search. Rates cover the five Local or eight DuckDB work slots, using
explicit fixed, per-input-row, per-canonical-wire-byte and per-potential-pair
time coefficients. Input quantities sum all port occurrences rather than keeping
one parent; identical content is not a fresh-import transfer discount. A join's
potential-pair basis is the product of its left/right input row estimates,
including a self join. This is an estimate basis for comparison/intermediate
work, not an output-count claim or a required physical Cartesian materialization.
Auxiliary key encoding, ordering, output transfer and cleanup still belong in
the appropriate disjoint work slots, with explicit fixed or quantity-based rates.
These are Host-supplied estimates, not calibrated performance guarantees. Capture
row count and canonical wire size come from existing retained measurements;
completed task row counts replace forecasts without re-admission or a new scan.
For uncompleted outputs, an explicit per-mille row estimate may be used. Its basis
is the input row count for unary operations and potential pairs for join; actual
completed cardinality replaces it. Non-root output wire sizes remain unknown,
not inferred from row ratios.
Missing coefficients or required quantities keep the total unknown. This policy
defers on unknown totals; explicit preference remains available through the
separate manual search API.

Estimate profiles and their nested work-slot arrays are copied at installation.
Local reservation envelopes are derived from selected execution limits; native
envelopes are explicit Host capacities and still checked against actual start
requirements. Neither is reduced by the forecast. Dispatch refreshes before
preparing the next ready task, preserving completed placements and the same
resource ledger. An unchanged state does not repeat search, and a failed refresh
cannot fall through to an older selection on a later call. Future offers remain
conditional: exact candidate applicability is checked when its input is ready.

Node executes trusted adapter operations. Checked graph validation, identity,
meaning, candidate compatibility and logical enforcement remain in MoonBit.
Execution reports distinguish task records, original failure, cleanup failures,
pending responsibility, strategy revisions and Program/publication status.

## Binary Local Compute ports

The captured execution state retains pending producer reads by checked input
port, not merely by consumer task. The Local path accepts a single inner-join
step with up to two completed input ports, including two ports bound to the same
producer. Data and control dependencies both precede dispatch; all request reads
must be the exact cached bindings. Closing either upstream port revokes pending
execution without invalidating independently completed descendants.

Result-retention accounting tracks every distinct parent task. Repeated logical
ports do not create a second parent holding token, and equal content from two
different parents does not merge tokens. The native adapter and placement
estimates must explicitly support both inputs before offering a binary native
candidate.
