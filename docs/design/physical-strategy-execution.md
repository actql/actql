# Serial physical strategy execution

## Scope and semantic ownership

A physical strategy realizes existing checked units; it is not a canonical Plan,
Program success, Run admission, or permission to publish Results. Data edges are
owned producer/target/receiver ports. Control edges come from checked incoming
success gates, not from reachability in the data graph. Both must be satisfied.
Splitting work does not create independent semantic success boundaries.

The execution profile is finite and serial, with one or two completed input
ports and one explicit final-step output per Compute. The common DAG does not
match operation names or demonstration step counts. Realization eligibility
belongs to each connector. Local can execute its existing supported sequences,
including sort followed by take; DuckDB retains its bounded filter/select,
single inner-join and group/count compiler profiles. Aggregate expressions,
aggregate filters and distinct counts remain unsupported by these profiles. Its
acceptance graph shares one completed acquisition X between
A and B, with C reading A. All Stage activation barriers remain mandatory even
when B has no data dependency on A. A task failure prevents further starts;
successful independently completed computations are not retroactively revoked.
Internal success records are not partial successful Program publication.

Each Compute exposes its exact final checked port, independently of operation
names. Local and fresh-import DuckDB dispatch
bind every ordered input port, including two references to the same producer.
Native static eligibility compiles all input schemas before cost comparison;
runtime preparation binds live inputs and the bounded null/cardinality preflight
configuration. The actual checks run once at Compute admission, after common
input guards and before native work. Their explicit work/scratch allowance is
charged to planning during dispatch preparation; an input guard failure does
not refund that allowance. The common native start also requires an output ceiling
no weaker than every checked join claim at its exact step, before reserving its
exact attempt. The synchronous start enforces the same rule.
A checked edge to an intermediate step is not silently
redirected to the final output. `captured_task_target` supplies this port to Host
diagnostics, completed statistics and resident imports without manufacturing a
completed output. Both local and DuckDB completions obey the same port selection;
acquisition continues to use its separate captured-source binding. Group results
can remain resident for subsequent filter/select or supported join/count tasks,
while independently retained Host results supply admission and completion evidence.
Two-input resident joins bind the exact ordered input set and share only actual
producer tables. This does not provide general aggregation or numeric reductions.

### Owned task obligations

The frontend's public `requirements → stage_requirement_operations` closure
already associates each disposition with its original stage, producer visit,
pipeline and step. `prepare_checked_dag` projects those entries using the
closure's corresponding requirement inventory, charging its bounded traversal
to preparation work. It includes only visits identified as local by
`program_identity_producer_is_local` and checks exact `unit_pipeline` ownership.
Imported producer prerequisite visits remain frontend-validated dependencies,
not additional operations of the importing Unit. No ApplicationCoverage search,
claim reconstruction, content-equality substitution or new canonical Plan is used.

`graph_task_operation_count/at` expose the original read-only occurrences and
dispositions. Join claims retain their owners; `captured_task_join_output_at`
enumerates step/ceiling pairs and `captured_task_join_output_limit(run, task,
step)` looks up one occurrence. Both start protocols require all selected
ceilings. These are execution obligations, not completed evidence.

Connectors inspect execution obligations before offering work and reject
unsupported ones; static resolutions are not pending runtime checks. Group,
window, expansion and other obligation families are not implicitly discharged by
finding a join limit. The current Local engine can enforce one selected join
ceiling at any supported step. Multiple join ceilings are retained by the common
DAG but excluded by Local eligibility until its engine supports them together.
DuckDB excludes unsupported step sequences through its existing static compiler.
Neither exclusion triggers an automatic execution retry or changes language
acceptance. New engine support changes connector eligibility, not DAG templates.

`execution_query.CapturedInputSource` encapsulates an already captured observation
without depending on a concrete issuer or planner implementation. It exposes
binding and live metadata, not a raw pre-capture output.
Its bindings compose the original output's live condition with the exact
issuer/attempt/observation check. `CapturedDAG` checks that this source belongs
to the same checked Program and bound acquisition as its root. Completed local
tasks are recorded only by invoking the selected existing Compute implementation;
callers cannot inject arbitrary completed outputs as task success. A candidate
must refer to the exact ProducerRead prepared for that task, not equal rows.

Capture implementations install a trusted, proof-typed port internally. Its
verifier retains the existing record-set, attempt, issuer and observation checks
and returns the exact completed output and retained canonical wire measurement.
The common port checks the QuerySequence's exact owned Program requests and
capture target; subsequent use must resolve to the same output handle and
measurement. This is trusted Host wiring, not an untrusted plugin verification
hook, and is not exposed through standard Program/Host execution configuration.
It neither accepts a success Bool nor turns CID/JSON values into output handles.
Third-party code in the same process remains part of the trusted runtime; opaque
types alone do not sandbox a malicious implementation.

Common DAG, Host and capture handoff dependencies exclude concrete connectors
transitively. `scripts/check-core-without-connectors.mjs` copies only the common
dependency closure into an isolated module and runs the pinned-toolchain check;
the connector and Node integration suites remain separate verification scopes.

The Node serial loop in `adapters/host-node` uses an immutable installation keyed
by exact capability registration handles. It neither selects an implementation
by name nor knows import, database or resident policies. Connector-owned Node
contributions implement execution and environment finalization; declarations in
their `node-bundle.json` manifests generate the separate builtin assembly.
Factories perform no I/O, and the standard composition entry does not accept a
replacement runtime, verifier or contribution through execution options.
Node loads only the selected modules through generated, build-time fixed import
functions. The full module selection and prepared configuration handles are
snapshotted before asynchronous loading. A failed load stops installation rather
than changing the candidate set. Cancellation observes any already-started import
and prevents subsequent imports, factories and dispatch. Workers use a separately
generated static composition; this does not add runtime plugin loading there.

An implementation's fulfilled Promise is not a completion proof. The loop checks
the common MoonBit DAG's retained completion before recording success. Failure
stops later starts, preserves independent completed outputs, and retains pending
cleanup handles until their recovery operation confirms release. Finalizers do
not retry computation. Closing results attempts all implementation releases and
the core output close even if one release reports an error. The low-level Node
coordination API is trusted runtime wiring, not a sandbox for arbitrary plugins.

Failure presence is separate from its JavaScript payload: `undefined`, `null`
and other non-Error rejections remain failures, with the first payload preserved.
Result invalidation on close is separate from recovery confirmation. Release
errors from finalizers, result handles and core output closure enter the recovery set; a
release without an explicit recovery handle stays unconfirmed and is not retried
implicitly. Cleanup attempts every independent handle, aggregates retry errors,
and retains incomplete handles. Concurrent cleanup callers share the same attempt.
Repeated close never repeats release work or revives result access.
When a finalizer throws without a recovery handle, its installed owner remains
unconfirmed even after result close. Neither cleanup nor the Workers invocation
wrapper retries that finalizer or reports successful cleanup on its behalf.

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

The `physical_host` prepared-dispatch state owns pending tickets independently
of connector payloads. Each ticket belongs to one exact driver, run, checked-ready
task and selected revision. Consuming it is one-shot; a stale revision, another
driver or a stopped run cannot use it. Invalidating a ticket does not erase search
history, completed results or physical resource usage. Tickets authorize only
the dispatch transition, not resource creation or successful task completion;
common task admission remains mandatory. Connector bridges do not keep a second
pending/consumed state machine.
The same common Host layer prepares fixed-input requests from checked graph
owners and receiving ports. It charges planning work and obtains exact completed
predecessor bindings without consulting a connector's generated sequence, SQL or
payload. Selected common consumer capacity is carried into the resulting request.

Synchronous no-I/O Compute is supplied through the connector SDK's opaque
`SynchronousCompute`. A trusted installed connector binds the exact selected
candidate, typed private payload, physical capacity, join ceiling where needed,
and executable operation. Binding does not evaluate inputs or grant task success.
The common DAG checks candidate/input ownership and the selected envelope, then
reserves capacity and a holding before invoking it. The operation is single-use
and checks current input availability before calling the connector. Local owns
its generated-sequence limits and execution; the common synchronous driver does
not import Local or interpret its payload. Returned data must be an engine-owned
`CompletedOutput`, not a success Bool, row array or caller-supplied CID.
The installed preparation entry supplies this handle before dispatch is staged;
the Host's synchronous execution operation does not interpret Local limits or
construct a generated-sequence executor.
Local's installed preparation entry is an opaque connector-owned configuration:
it retains the exact capability registration, a bounded snapshot of sequence
handles, and its execution/measurement settings. Candidate construction, selected
payload binding and capacity preparation happen inside the Local connector.
Configuration slot numbers are private lookup keys; they never replace the exact
checked-owner comparison against the incoming fixed-input request. Installation
does not run admission, and registry closure disables later preparation without
revoking independently completed outputs.
DuckDB preparation similarly retains its physical input names, compiled join,
input validation limits and output ceiling inside an opaque connector plan.
The Host reads the required preflight work and charges the common planning ledger
before invoking the plan's one-shot binding operation. The binding request and
limits cannot be replaced between compilation and input validation. Static
unsupported-expression and resident-name diagnostics are produced by the DuckDB
connector; Host configuration transports the reasons without interpreting SQL
name-resolution rules. No native execution or completion is implied by candidate
selection, and all task reservations and completion checks still apply.

This is trusted connector-author wiring, not a callback accepted from a Program
or an ordinary Host execution request. It cannot sandbox an arbitrary plugin in
the same process. The no-I/O contract excludes network, DB, asynchronous cleanup
and fresh reads; those require the asynchronous execution lifecycle. Conservative
capacity declarations do not replace the request's logical guards or completion
evidence checks.

The common asynchronous task lifecycle owns the exact task reservation,
and exposes transfer charging, settlement, completion and close through an opaque
`TaskExecution`. The handle is created only by common start admission; it cannot
be constructed from a task number, raw transport attempt, output or callback.
Every operation rechecks its exact owning run. Concrete transport bridges recover
their installed execution, but do not provide separate backend-specific lifecycle
implementations or compatibility wrappers.

The lifecycle also owns
settlement state, provisional holding, successful output installation and final
disposal. Its running handle is not a concrete connector attempt. Private
implementation hooks request cancellation, dispose buffers, confirm reusable
inputs and produce an already verified engine completion; they cannot settle
the common ledger by returning success alone. The common completion boundary
also checks the output's exact bound owner, retained port, fixed-input binding
identities and current liveness.
Installed asynchronous implementations bind their typed selected payload into
the SDK's opaque `PreparedExecution`. Its preparation is single-use and rechecks
registration and fixed-input availability. `start_captured_execution` validates
the exact candidate, checked inputs, join ceiling and required capacity before
invoking that preparation under a common reservation. The returned transport
handle remains implementation-typed; the DAG retains only common lifecycle
operations. A failed reservation does not consume the preparation. A failure
after admission stops further task dispatch without refunding attempt work.
Shared-resource selections additionally require an opaque `ResidentExecution`
bound to the exact run, task, candidate and borrowers. The common start checks
its required capacity and selected resource profile, allocates provisional
output only after reservation, and claims borrowers only on successful start.
Omitting or exchanging this admission cannot bypass a selected reuse contract.
An offer declares the resource-side output-copy capacity separately from Host
retention. Whole-strategy composition uses that declaration for resource capacity
and copy lifetimes; it never infers physical-copy size from equal logical content
or from the Host envelope. Start admission checks the concrete materialization
requirement against the selected copy allowance before claiming inputs or
reserving task work. The DuckDB implementation uses its existing conservative
result allowance for both declarations, but that equality is not a planner rule.

The SDK operation record is trusted connector-author wiring, not an ordinary
Program or per-call Host option. It does not isolate malicious code in the same
process. Completion still requires engine-produced output with exact provenance,
and returning successful operations cannot itself settle reservations or create
a DAG completion. Scoped `TaskPublication` has no public constructor or output
getter; it is issued only after output and holding verification and expires on
return from the publication operation.
Synchronous Local and asynchronous realizations use the same private output
installation operation. It validates the completed port and input identities
before implementation-specific publication, then attaches the owned holding and
records task success together. Allocation timing and failure cleanup remain with
the respective execution lifecycle; neither path exposes a holding-less success.
This port check supplements, rather than replaces, the implementation's exact
input/attempt/transport evidence validation. Cancellation alone never releases
execution reservations. Confirmed execution cleanup may release execution
capacity while keeping completion scratch and provisional output accounted.

The DAG stores only common execution handles, not a parallel array indexed by
concrete backend attempts. `connectors/duckdb/driver` owns the opaque DuckDB task
handle, attempt construction, cancellation and verified completion operations.
Its handle binds the transport attempt to the common execution. Provisional
shared output and borrower settlement belong to that common execution, not to
the DuckDB attempt wrapper.
Materialization plans and concrete configuration stay in the connector as well.
The common resource preparation invokes an installed typed factory with its
allocated ordinal, without interpreting SQL. It retains only the operation that
binds a verified completion to the physical representation. That binding is
checked against the exact completion supplied to the binding operation; equal contents or
a separately restricted output alias are not sufficient. The engine checks this
identity without exposing mutable storage or copying rows. Transport-facing
query retrieval remains in the DuckDB driver, gated by the owning execution's
availability, and final disposal drops the driver's provisional plan reference.
Ledger and completion operations validate that exact execution against the DAG;
a raw transport attempt cannot be used to recover or replace the binding. Once
disposal and settlement both finish, the common execution detaches its hooks and
the execution drops provisional resident references. A retained closed handle cannot
reactivate work or release another task's reservation.
Cleanup preparation is split at the same ownership boundary. The common driver
selects the exact last-use allocation set and charges its graph traversal. The
connector prepares physical removal operations using a copied list of opaque
table handles (not copied rows). Only successful preparation retires the original
set; failure leaves every member available. The common driver rechecks ownership
and liveness before that transition. DuckDB DROP generation and its configured
SQL limit belong to the connector driver. Preparation and retirement are not
acknowledgements of native removal or authority to release reserved capacity.

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

Resident input preparation selects the exact producer storage in the common
boundary, then invokes trusted connector preparation with a bounded ordinal.
The DuckDB driver owns physical table naming and import SQL. The common boundary
checks exact storage affinity and current environment state before allocating
shared capacity; a rejected preparation cannot leave a table registration or
consume a table ordinal. Reusing equal-content storage from another preparation
is not accepted as the owned input.

The common table retains only `ProducerStorage`, its environment generation,
producer position and shared allocation. `physical_strategy` does not import the
DuckDB adapter or expose its import type. A connector-owned `DuckDBResidentStore`
keeps physical import preparations separately, indexed by checked producer
position and verified against exact environment and storage references. Equal
content, another store, or a replaced preparation cannot recover a physical plan.
There is at most one current preparation per producer position; corrected
unstarted preparations replace that entry rather than growing an attempt list.
The Node transport pairs a common table with its exact store in an opaque handle.
Closing an environment keeps these preparations available for cleanup; they are
discarded only after common resource settlement succeeds, not on cancellation.

Resident receiver view preparation likewise belongs to the DuckDB driver. Its
trusted preparation checks exact import and ProducerRead affinity and measures
the actual plan bytes. `DuckDBResidentInputs` holds concrete plans and the common
borrow-set handle without exposing a constructor. View callbacks receive the
common table handle, not a DuckDB import. Before invoking them, the common borrower
resolves the input against the table's exact `ProducerStorage`, rejecting a
different producer allocation even if its contents match. This bounded metadata
projection performs no row copy or value re-admission. The common borrower also
rechecks environment, storage and input liveness before acquiring a shared borrow;
it stores no view plan. The ordered input-set boundary enforces the cumulative measured-byte
allowance and returns earlier borrowers if any later port fails preparation.
These preparation callbacks are trusted connector wiring, not Program-provided
verification callbacks or permission to perform I/O.

The common resident input set is bound to an exact `FixedComputeCandidate`, its
checked task owner and ordered request input handles, not to a DuckDB query
payload. Resident execution admission matches that same candidate. The connector
additionally checks its chosen typed payload and concrete imports before preparing
receiver views; equal content cannot replace either ownership relationship.

Connector execution diagnostics cross the common DAG as `Implementation(Error)`.
The common driver records failure and stops dispatch without interpreting a
provider-specific variant. DuckDB owns `DuckDBFailure` and its typed diagnostic
projection, preserving detailed preparation/guard/receiving errors without
string conversion. An implementation error is never evidence of completion or
permission to retry another provider.

Resident result materialization keeps its physical table name, SQL and storage
construction limits in a connector-owned opaque plan. The shared output lifecycle
retains its allocation, commit state and pending input cleanup, and checks exact
task/input completion before binding the completed storage to that plan. The plan
alone is not completion evidence or authority to publish a reusable copy.
The binder returns the exact completed `ProducerStorage` to the common boundary;
physical SQL and import metadata stay in the owning connector store. Common
publication checks the storage/output association and atomically installs the
retained table only after the existing completion and commit conditions succeed.
The same boundary applies to receiver views: common borrowing retains the owned
input lease, while the connector retains its read plan and obtains its SQL. A bounded
measurement of that plan charges the existing cumulative preparation allowance;
the common driver does not inspect SQL to decide input identity or reuse rights.
Each resource profile retains an opaque `connector_sdk.ResourceBinding`, whose
exact capability registration identifies the implementation. Binding identity,
cost-profile identity, logical input identity and the later provisioned environment
are distinct. One implementation may have multiple bindings; equal names, costs
or content CIDs do not merge them. Creating a binding is pure trusted Host wiring,
not resource provision, permission to access a source, a read view or a start
permit. Concrete resource configuration stays with the connector. Attaching a
profile to an offer from another registration is rejected before comparison.
The environment retains the selected binding throughout reservation and cleanup.
Closing its implementation registration rejects new provision and pending
confirmation, without discharging an existing reservation or rewriting the
binding needed for recovery. Replacing a released environment with another binding
cannot recover its old copy; accumulated transfer usage remains charged.

The common DAG owns a collection of environments keyed by exact resource binding,
not a single environment selected by implementation name. Simultaneous bindings
have separate capacity reservations, copy inventories and settlement. Another
provision for the same binding is rejected until the previous environment has
settled, including while cleanup is pending. Settling one environment removes only
that environment; it does not release another binding's copies or reservations.

Whole-strategy composition accounts for preparation and imports separately for
each distinct profile. A single binding cannot promise conflicting profiles in
the same strategy. New environment capacities are cumulative; serial temporary
work contributes a peak, not a fictitious shared environment. Outstanding cleanup
for every existing environment applies independently of the remaining task
placements, including an all-Local selection. Equal input contents on different
bindings do not discount transfers. The DuckDB contribution keeps separate Node
environments keyed by the exact selected resource binding. Its installation can
offer multiple bounded resident profiles, but cannot replace a profile for an
already configured binding. A and B on different bindings import X separately;
A and C on one live binding may reuse A's retained copy. The common serial Host
does not interpret those database or import details.

The physical ledger operates without
depending on a planner, driver or concrete connector. These are opaque owned
handles: callers can inspect immutable limits, usage, ownership and availability,
but cannot mutate counters or manufacture a reservation or holding. Settlement
releases unused reservations, not already consumed transfer or independently held
output. Releasing a holding changes its availability, not its owning ledger.
The strategy layer additionally binds those resources to checked tasks and selected
attempts; a ledger handle alone is not execution permission or completion evidence.

`connectors_builtin.open_configured_compute_host` accepts an already configured
module installation, its exact registry, common consumer capacity and inspection
bounds. It uses the installation's original driver; a second driver or reconstructed
module owner cannot replace it. There is no mandatory pair of implementations or
provider-specific setting in this entry. Each connector module copies
its sequence-handle container rather than borrowing mutable caller slots.
Configuration dispatch is generated from connector-owned declarations: the
complete registration subset is checked before invoking pure connector factories,
and the resulting opaque modules supply their own paired contributions. The
application supplies typed settings but does not choose construction functions
through a handwritten backend branch. Configuration failure does not create a
provider environment or task; any already charged static planning work remains
consumed.
The Host does not retain a duplicate sequence array; task/port topology comes from
the existing checked graph. The next-dispatch operation
recovers the installed preparation entry by exact registration, never by name or
registration position. Local and DuckDB preparation entries retain their own
compiler and binding rules; a lookup is not permission to start or complete work.
The installed preparation callbacks capture connector modules, not the enclosing
Host configuration. Their common invocation context is `Unit`; an implementation
does not receive another connector's channel, limits or mutable Host policy.
The common `physical_host.DispatchHost` fixes the preparation installation and
input-capacity policy. It selects the next checked-ready task from the current
strategy, binds actual completed inputs, and issues `PreparedTaskDispatch` only
after rechecking the returned work token. Standard transport preparation and
independent Compute implementations use this same operation. A task handle also
belongs to the exact Host installation: sharing a driver or registry does not
permit a second installation to recover its payload. Miswired preparation from
a different run stops the driver rather than leaving its new ticket usable.
Preparation payloads stay in typed, implementation-specific `DispatchChannel[T]`
slots. The common `DispatchWork` token contains only the exact driver owner,
registration, task and revision, not a closed backend variant. Recovering a
payload checks the exact channel token and driver, consumes the current dispatch
ticket once, and leaves normal reservation/start admission mandatory. A foreign
channel, closed registration or stale ticket cannot recover the payload. The
single slot may replace a stale, unstarted preparation; it cannot contain an
active attempt or cleanup responsibility. This boundary neither copies row data
nor creates resources while preparing a dispatch.
The Local connector's `LocalDispatchModule` owns its sequence installation and
typed synchronous channel. It validates the exact checked task owners at
installation, binds the task's selected join ceiling during preparation, and
executes through the common synchronous reservation/completion boundary. Both
the standard Host and bundle-based installations call these connector operations;
they do not recover Local compute payloads or duplicate its preparation logic.
DuckDB's `ComputeHostConfiguration` and `StrategyComputeHostConfiguration` are
owned by `connectors/duckdb/driver`. These opaque handles retain its exact
candidate, neutral completion preparation, result limits and transport configuration.
Only the connector driver interprets them to borrow resident inputs, calculate
required scratch/retention, or start through the common resource boundary.
The standard Host routes the selected handle to that driver rather than owning
a second configuration or start implementation.
`DuckDBDispatchModule` also owns bounded static compilation, rejection reasons,
the retained sequence handles and its typed preparation channel. Preparation
checks the exact request owner, current selection and registration before input
preflight. A returned configuration is still only prepared work: taking it
consumes one exact channel ticket, and normal resource/start admission remains
mandatory. Equal modules or shared registrations cannot exchange staged payloads.
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

The standard Node `adapters/host-node/entry.mjs` entry executes that finite serial
sequence through configured modules. Its bridge is generated in
`connectors_builtin_node` from the common bridge template and connector manifests.
The common template, serial driver and Host contain no implementation-specific
configuration or dispatch branch. Generated typed entries route to each module's
own execution channel. The numeric and Local in-process modules complete work in
their connector-owned entry; external transports retain explicit settlement.
No fixture,
source connection, replacement runtime or verifier callback enters the driver.
It stops on the first failure and preserves that failure, including any live
cleanup handle, alongside internal completed task records. Its result is labeled
Host-task completion/failure, never Program success or partial publication.
Closing the result closes its task ports but not the caller-owned capture.
The Local/DuckDB application profile is a dedicated example under
`connectors/duckdb/example_host`, not a standard Host configuration or compatibility
entry. It constructs the same standard installation and owns only example policy.
The former top-level `duckdb_host` and `duckdb_host_node` packages are absent.
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
Shared preparation, copy and recovery phases use bounded `SharedWorkEstimate`
inventories supplied by the implementation. Each phase can contain any bounded
number of disjoint work slots or bundled lines; the common layer does not define
provider-specific slot counts. Overlapping lines are rejected, and absent slots
or durations produce unknown cost. The inventory is charged to planning before
inspection, snapshots nested arrays, and retains the exact graph owner. It is an
estimate, not proof of an available copy, a reservation, or completion. Reusing
the same estimate object does not deduplicate distinct physical work. Whole-plan
composition still counts only actually shared preparation/copies once and keeps
unsettled recovery costs for every alternative, including alternatives that no
longer use the retained resource. Bounded explanation includes these inventories
alongside their assessed totals.
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

The common Host collects future-task offers from an immutable installation of
proposal callbacks. Each callback receives the task and known/unknown input
quantities and may propose zero or more representations. Collection preserves
installation/alternative order, bounds the total offers, and rechecks exact
run, task and registration ownership and registration liveness after callbacks.
It does not recognize provider names, work-slot counts or representation kinds.
The caller's bounded estimation pass accounts for planning work; proposal
callbacks must not start I/O. An offer is neither a future input CID nor a permit
to bypass later capacity or completed-input admission.

The standard dispatch can install a bounded declarative estimate profile before
its first search. Its composition supplies Local and DuckDB proposal entries;
the Local connector calculates its actual sequence capacity and five-slot offer,
and the DuckDB driver constructs fresh/reusable eight-slot offers. Rates use
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

Estimate profiles are installed as opaque `physical_cost.RateSchedule` values.
Their `WorkRate` inputs and nested work-slot arrays are copied after bounded
validation; returned estimate lines cannot mutate the installed schedule. The
owning realization supplies the work inventory, while the common cost library
checks disjoint coverage and evaluates the same linear rate rules for any
inventory. Missing coefficients or needed quantities remain unknown, zero
coefficients do not demand a quantity, and overflow is an explicit failure.
Each connector's estimate module owns its installed schedules and realization
capacities. The standard composition captures these modules in registration-bound
proposal callbacks with a unit context; it does not pass the complete Host or
mutable planning policy back into candidate generation. Common refresh tracks
observed cardinality, future-output estimates and bounded search state. DuckDB
owns the fresh/resident alternatives and the resident profile association, which
may be installed only before strategy history exists and cannot be replaced after
installation. No estimate module grants execution, creates a resource, supplies
a future completed input or relaxes dispatch admission.

The connector's contribution factory pairs preparation and proposal callbacks
over that same installed module. Composition supplies diagnostic error projections
but does not construct the callbacks independently. Realization-specific static
exclusions, including their display labels, are supplied by the owning connector;
the Host does not infer a second realization from a backend-specific profile flag.

Typed Compute composition is generated in `connectors_builtin` from declarations
owned by connector packages. The standard composition and the independent numeric
integration use the same assembly entrypoint; common Host and planner packages
do not import this concrete composition root. Its optional typed module arguments
select an immutable implementation subset, and all entries are validated by the
SDK. Registry order, rather than manifest file order, determines the resulting
entry order. Connector-specific module construction is distinct from this pure
registration step and does not become resource creation or dispatch permission.

The same declarations provide typed execution entries and optional estimate-policy
preparation/installation. Generated execution routes to the configured module's
exact channel; a missing implementation cannot consume a dispatch ticket. Prepared
estimate installations capture their module and diagnostic projection, keeping
the policy's concrete type inside generated composition. Standard fresh and shared
resource policy configuration uses these entries, while bounded rate validation
and common adaptive-state installation retain their existing ordering and charges.
No concrete policy module is retained separately by the standard Host.

`physical_host.AdaptiveDispatch` owns cardinality propagation, the immutable
proposal installation and bounded refresh history independently of connector
configuration. It obtains initial statistics from the exact captured DAG and
updates them only from completed task outputs; callers cannot replace these
observations with unrelated values. The output-fraction estimates are copied at
installation. A successful refresh in an unchanged execution state is a no-op;
a failed refresh stays failed, stops the associated driver and never reopens the
previous selection. Completed results and cleanup obligations are retained. Both
standard composition and independent Compute bundles use this common policy.

`physical_host.ComputeHost` binds that optional policy to one fixed contribution
installation and one dispatch owner. Its internal projections preserve the same
registration set for proposals and preparation. Registry ownership is checked
even for an empty implementation set. Policy installation is one-time; next-task
preparation checks pending work and refreshes before retrieving an implementation.
Failed refresh cannot reach preparation or reopen an old dispatch. Connector
execution consumes the existing opaque dispatch owner, not a mutable Host context.
The standard application retains connector configuration only, not another copy
of the adaptive installation or failure state.

Compute bundles supply their pure preparation and proposal callbacks together as
`physical_host.ComputeContribution`. SDK projection derives each entrypoint set
from the same immutable installation without accepting replacement registrations.
Order, exact registry ownership and closure are retained by every projection;
projection neither invokes execution nor authorizes resource allocation. The
standard Host does not register its proposal implementation set independently
from preparation. Connector-owned estimate configuration is installed once before
strategy history exists, bound to the exact dispatch module, and cannot be swapped
between otherwise equivalent module instances. Configuration retains only immutable
schedule data, not a back-reference cycle to the dispatch module.
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

## Independent numeric connector completion

The bounded reference Compute connector evaluates numeric-field greater-than
literal predicates and numeric projections without delegating to the Local or
DuckDB executor. Input/output guards use the common fixed-producer measurement
session. Demanded operand and predicate values are measured in the evaluation
loop without reevaluation; their bounded physical measurement budget is separate
from the input/output measurement budget. Neither budget is a substitute for the
Host's execution reservation or a selected shared fragment contract.

Only successful measured material can be sealed, once, through the connector's
internally installed output verifier. Sealing checks exact generated owner and
input bindings and requires the upstream input to remain available. A sealed
result owns its retained rows and its own revocation state; closing the upstream
does not revoke that independent result. Closing the result prevents new
downstream execution without invalidating already completed descendants.

This connector completion is not a DAG success notification. The common driver
must still enforce selected-attempt ownership, reservation and holding attachment
before publishing task success. Raw selected positions or admitted rows carry no
completion authority.

The reference implementation contributes a Compute-only bundle. Its installed
entry binds an opaque numeric plan to the exact common request and registration;
the common cost selector does not inspect that payload. Requests selecting a
common fragment are rejected because this specialization does not implement that
fragment's logical work/live-value metering. Common rows/value guards still apply.

Execution preparation declares bounded allocation-unit capacity from the selected
kernel and measurement limits. It borrows fixed input storage and charges no
transport for that in-process access. The common driver reserves capacity before
creating the attempt. Kernel execution is one-shot; cancellation or confirmed
settlement prevents a subsequent start. Completion and holding attachment remain
common-driver operations, and cancellation alone does not settle its reservation.
Allocation-unit capacity is not a claim about target-runtime heap size or RSS.
