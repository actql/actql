# Catalog-backed Table Effects

## Scope and owners

A Table action consumes one checked Relation as one Effect operation, including
an empty typed Relation. It does not emit item keys or split the action into row
writes. Catalog create is not the existing record-oriented `create` action.
The first actions are create-if-absent and whole-table replace with an expected
Table identity and generation. They share existing approval, current authority,
durable dispatch, uncertainty, reconciliation and cleanup governance. A Table
driver is a physical adapter, not another Run or Effect state machine.

The initial installation is a single Host with a local warehouse and a
SQLite-backed Iceberg Catalog. PyIceberg and PyArrow are explicitly installed
Table-feature dependencies, not dependencies of Core or the ordinary SDK.
Iceberg metadata, manifests and Parquet files are the durable Table's source of
truth. A private Relation snapshot, a Named Result and a durable Table have
different identities and lifetimes. External writers, Catalog migration, schema
evolution, incremental writes and a dbt adapter are later units.

Local Table Source and Effect installation belongs to the Local Connector.
Its `host-bundle.json` declares the two roles and the finite physical worker
assets. The common Host selects those declared roles; there is no second
Table-only installation table or fallback to an older built-in profile.
The Python Iceberg implementation stays behind the Local physical boundary,
while shared validation, approval and Effect governance remain common.

## Operation and publication identity

`actql-table-operation/0.1` binds the saved logical request scope and Effect
identity, installed Catalog identity, exact namespace/name, create/replace
action, expected Table UUID and generation (replace only), captured input
Artifact and a closed `input_carrier: {kind, cid}` reference, schema, data policy
and storage mapping. The reference admits Relation, Graph, Vectors and Events;
its kind is part of the complete request preimage and must match the checked
input and Connector-validated mapping. This does not install a writer for every
kind. The current captured input consumer and Local physical declaration support
Relation create/replace only; unsupported operation/kind pairs are refused
before writer invocation and persistent reservation. Its
`request_cid` excludes only that root self-field. Repeated statements retain
their distinct checked Effect identities; a table name is not an idempotency
key. Current authority remains a separate prerequisite, never reconstructed
from saved values or refreshed by changing the original request.

This pre-v0.1 contract replaces the retired `input_relation_cid` operation
shape without aliases, implicit conversion or a compatibility reader. Request
identities and dependent receipts change with the new complete preimage; saved
operations are not relabelled with new CIDs. Historical evidence remains bound
to its original source revision.

A Table's UUID is stable through replace. A generation is the content CID of
the exact immutable Iceberg metadata file published by the Catalog, not a
logical row-content CID or merely the current data snapshot ID. Empty typed
Tables need no fabricated data file or non-null snapshot ID. A receipt identifies
the original operation, Catalog, Table UUID, published metadata generation,
logical schema and physical mapping. A nullable snapshot ID is represented as a
decimal string when present, avoiding binary64 loss of Iceberg's long IDs.

Create publishes only if the name is unused. Replace verifies the expected UUID
and metadata generation and preserves schema CID. Conflict is a typed rejection;
there is no automatic rebase, overwrite, approval renewal or send against a new
head. The original operation record survives subsequent commits and is separate
from the Table head. Same-operation lookup returns its recorded result; current
head equality is neither proof of that operation's commit nor proof of failure.

## Presence and supported physical types

The physical mapping is sealed and binds the complete logical Relation schema,
including Required/Conditional independently of nullable. Field IDs, not column
names or positions inferred on reload, bind each logical value column to its
Iceberg value field and, for Conditional columns, a required boolean companion.
Companion names use a reserved physical namespace and never overwrite user
fields. The Local physical issuer selects consecutive IDs in canonical schema order,
with each companion immediately after its value field. The pinned new-table
writer verifies Catalog schema assignment against this sealed mapping before
writing; silently renumbering an approved mapping is not allowed.

For a Conditional column, `(false, NULL)` is absent, `(true, NULL)` is present
NULL, and `(true, value)` is present value. `(false, value)`, a missing or NULL
companion, an absent value field, an unexpected field-ID/type mapping, and a
present NULL contrary to logical nullability are rejected. Physical schema and
Parquet columns are inspected before Iceberg default projection can erase those
distinctions. Required logical fields have no companion and cannot disappear.

The first writer admits flat boolean, finite binary64 number and exact string
columns, with nullable and column presence preserved. Other types, including
nested objects/arrays, references, decimal and temporal types, remain explicitly
unsupported until lossless encoding, admission and reload are implemented.
Refusal happens before Table staging or commit, independent of actual rows or
empty input. String values and keys are not configuration-normalized. Duplicate
rows remain duplicates. Iceberg physical order is not a query-order guarantee.
Generic Iceberg readers see companion fields; they do not automatically acquire
ActQL's missing-versus-NULL semantics.

## Binding a captured Relation

### Table-only closed input boundary

An ordinary Named Result continues to require every published column to be
Required. Its field projection closes both delivery and ordinary Result-backed
Effect consumption. Table materialization must not weaken that rule or silently
publish a Conditional column as nullable.

A Table operation instead needs a closed, checked Relation input which can
retain Conditional columns. Its authored binding and finite selected column set
must be resolved by the common checker. The complete input schema includes each
column's value contract, nullability and independent presence guarantee, even
for empty input. Sample values, `IS NOT NULL`, and a physical mapping cannot
issue that schema or promote a Conditional column to Required.

The structured declaration is stage-local
`table_inputs: {name: {from: binding, fields: [column, ...]}}`; a Table `store`
selects it using `from: {table_input: name}`. Its namespace and checked type are
separate from ordinary Results, even when names coincide. The closed declaration
has no order override, publication metadata or authored presence assertion.
Stage/Program semantics include both the declaration and the private source
choice. The common declaration-count, work, nodes and text limits include its
admission and exact source-owned retention; no second accounting owner is added.

This input is private operation material, not another public Named Result. Its
completed export and capture use the existing Relation, Store, Effect input and
Table binding owners. The exact source occurrence, closed projection, logical
schema, content and effective Data Policy must bind the operation and approval;
an adapter cannot replace them with an equal but foreign export or a fabricated
Result Artifact. The ordinary Result-derived input remains valid for all-Required
Tables, but is not a compatibility fallback for the private input.

Omitted cells remain absent, explicit NULL remains present and nullable, and
actual values retain their checked type. These facts survive capture, durable
recovery, physical field-ID mapping and a later Table Source read. Unknown commit
and cleanup custody do not change. A Table-only input capability must not make
arbitrary row Effects, downstream stage imports or public delivery consumers
accept sparse Results. Structural Program admission and executable capture must
both implement this distinction before sparse public materialization is claimed.

Storage mapping issuance consumes the existing completed Relation export
receipt, not adapter-authored schema JSON or an asserted schema CID. It uses
the complete checked schema, including conditional columns that no actual row
contains. The same schema yields the same mapping for empty and nonempty input.
Unsupported declarations and physical-name collisions are refused before
staging. The schema identity preserves logical constraints that are not part of
the physical boolean/double/string discriminator.

A new Table Source must use that complete logical schema, not infer one from
the physical mapping or sample rows. Publication must retain the common owner's
canonical field-contract map under its schema CID in the durable Table metadata.
On a later read, the common owner must re-admit that map and check its identity,
column names, value contracts and presence against the selected generation.
Missing logical metadata is a refusal, not permission to synthesize unconstrained
primitive types from Iceberg fields. The Source declaration and the runtime input
must agree even for an empty generation.

The live export supplies its exact canonical schema wire; recovery retains the
same wire with the original mapping and operation. The common owner checks it
against the approved schema CID before dispatch. The physical writer requires
this material and stores it as `actql.logical-schema` in immutable Iceberg
metadata. It checks correspondence with the sealed field-ID/presence mapping,
but does not issue logical contracts or infer value constraints. Replace requires
the same saved schema wire. A reader receives those exact bytes and must still
admit the complete logical contract through the common Source owner.

The Source declaration carries the saved field map in the closed
`actql-relation-schema/0.1` carrier-schema body. Required fields retain their
complete value contracts; Conditional fields retain their separate presence
wrapper. The declaration producer and Check Environment use the same bounded
field-map reader, rather than separate primitive-type approximations. The
logical field-map CID, carrier body CID and Contract Envelope CID identify
different preimages. Existing object value contracts remain all-fields-required;
this form serializes the existing Relation presence contract, not optional
ordinary objects. Physical generation resolution alone supplies no read grant.

Row acquisition uses the existing exact checked-input owner for both required
and conditional columns. An omitted conditional cell enters presence-aware row
admission; explicit NULL still goes through the column's nullable value contract.
Required omissions, undeclared fields and type violations refuse the acquisition.
The existing cumulative capture bounds include presence containers, and failed
input admission cannot hand off earlier rows as a completed partial Source.
This does not relax required fields of ordinary object value contracts or make
conditional columns available to ordinary expressions without a schema guarantee.

The common Host binds a Table request to the exact checked `store` member,
captured local Result Artifact, issued Effect identity and logical request
scope. It checks the request's Artifact, logical Relation, schema, mapping and
effective Data Policy against these owners. Another member's identity, an equal
but foreign captured owner, or a resealed request with substituted input facts
cannot supply that binding. The binding retains the existing owners; it does
not establish a second input-custody or execution owner.

The selected Connector issues and admits its physical storage mapping before
binding. Shared input admission validates only the exact mapping CID, schema
CID and Carrier kind; it does not issue or interpret backend field layouts.
The first Table consumer accepts Relation input only. References for other
Carrier kinds do not establish a supported writer or authorize flattening.

This is input/content binding only. Target installation, approval, current
authority, retained source availability, durable dispatch and Catalog commit
remain separate gates. A valid binding must never be interpreted as permission
to stage or write. In particular, existing row Effect execution cannot stand in
for the Table operation: the whole Relation, including typed empty input, is one
operation, not zero or one dispatch per row.

## Durable commit and file custody

The catalog-backed profile binds the complete Table operation to one existing
Effect Preview item slot, including for typed empty input. Its correlation is
the request CID string and its intended value is the complete sealed operation.
It requires `approval: "required"` and `count: 1, max_items: 1`. Replace carries
the expected generation as the existing version guard; create has no version
guard and still requires atomic name absence at commit. The existing Preview
semantic CID and item dispatch-key owner bind that content without introducing
a Table approval or Ledger owner. Before/after row states are not applicable:
the item describes a whole-Relation operation, not a fabricated data row.

The Table installation's pure authoring connection resolves each member from
the checked Program descriptor and matches its target, Mapping reference and
Mapping contract to the installed binding. It derives operation input facts
from the actual captured local Result Artifact and issued storage mapping,
then uses the common Preview authoring and captured-input binding owners.
The member count is one even for zero input rows. The request CID correlation,
required approval and expected-generation guard are sealed before apply.
Authoring does not stage files, dispatch, establish current authorization or
replace the installed capability's separate admission.

The selected bridge supplies synchronous `issueStorageMapping` and
`admitStorageMapping` hooks. Live commit preparation reuses the bound mapping
bytes rather than issuing a new physical layout after approval.

The Table Preview's `result_artifact_cid` names the semantic completed Result
Artifact bound by the operation. Its separate source binding comes from the
actual Run-bound physical source Artifact. Substituting the physical Artifact
CID for the semantic one is a foreign-input refusal, not a transport fallback.
Durable source holdings retain both through the existing result-aware capture
owner. Installations must not obtain their requests from per-row write mapping
or invent a row to represent an empty Table.

The installed Table hooks project the completed computation and recovered
capture into the existing installed Effect Site. Installation metadata binds
each checked Effect member and Mapping to one Catalog/name and create or
expected-generation replace action. Capability identity also binds the runtime,
installation and these exact targets; a changed capability cannot resume a
saved Preview. Member ordering comes from checked ordinals, not installation
array order. Source-free authoring does not fabricate Model provenance.

Capture prepares bounded physical material but performs no Catalog observation
or write. Recovery reads the original Catalog operation under current authority
before using the common durable frontier. Only Ready members refresh current
target guards; a committed create is not rejected merely because its name now
exists. Dispatching/Unknown members reconcile rather than claim another send.
The same Site cleanup custody serializes concurrent retries, retains pending
physical handles, and closes the Ledger only after verified cleanup. Immutable
Table generations remain Catalog-owned after temporary Run handles are released.

The Table input binding is paired with the existing checked captured Preview,
including its exact live source occurrence. A different member, substituted
operation, row-oriented inventory, missing approval requirement or different
generation guard is refused. The retained subject is the complete Effect Set
Preview CID, not the Table name or request CID alone. This binding is not an
approval grant: current installed target validation, permission and approval
decisions, source availability and durable claims remain required at apply.

For process recovery, the same private capture record retains the original
sealed storage mapping, operation and canonical schema wire for each Table
member. The closed material record contains `mapping_wire`, `operation_wire`
and `schema_wire`; omitted schema material is refused without reconstruction.
A recovered typed
Table view derives the operation from that member's sealed Preview, re-admits
the exact mapping through the selected Connector's `admitStorageMapping`,
without regeneration or substitution, and matches the original request scope,
semantic Result Artifact, schema, logical Relation, policy and physical source occurrence.
Capture validation and Table material admission have separate explicit limits;
recovery does not widen the Table contract's limits. Missing material or a
different operation is a refusal, not a request to regenerate Compute or schema.

This view is immutable content, not live input availability or a send permit.
Reads recheck the existing capture/Result owners after Store awaits, and use
the same physical-holding read owner and exact bytes/logical CID checks as live
Table inputs. Release invalidates read availability; no new capture or cleanup
owner is created. Receipt projection can still check the original operation and
captured row count after release, without allowing another dispatch. Approval,
current target authority, durable claims and Catalog reconciliation remain the
existing apply owners' separate responsibilities.

Recovered Table dispatch uses the same physical preparation and approved
whole-set dispatch binder as live execution. The recovered input is read only
through its exact capture/Store handle. Current process-local owners are
rechecked synchronously after target observation and immediately before the
durable dispatch claim; the recovered apply owner separately confirms physical
holdings and current authorization. The immutable Table view itself is never
used as an availability or permission getter. Terminal release also relinquishes
the recovered Result/schema leases through the existing result owner; deleting
durable capture records alone is not release of live prepared handles.

Prepared request and captured input are retained by existing owners before any
dispatch. Table staging, metadata publication and Table writes require approval
and current write authority; pre-approval Table writes are zero. Retaining Run
input is not Table publication. Dispatching/Unknown never authorize another
commit. Recovery reads the original operation's durable Catalog evidence under
current read/reconciliation authority and uses existing Effect transitions.

Original-operation reconciliation uses the exact checked Table Preview and the
validated complete history of its original possible dispatch. It does not create
an intent or claim another send. Current evidence-read authority precedes the
Catalog lookup and is checked again after it; the physical reader needs only the
sealed original operation, not reconstructed input or a new writer. An absent
original record remains unknown. A positive receipt is checked against the
immutable operation and row count before durable evidence custody, then the
existing Table outcome and terminal Ledger owners settle that saved evidence.
Concurrent or delayed observers cannot overwrite the first saved response or
create a second terminal revision. Saved malformed evidence is retained rather
than replaced by a lookup; that case remains a separate recovery obligation.

The installed Host connects public `Run.reconcile()` to this observation of
the original Effect continuation. It reopens the retained capture through the
same Store owner, leaves the completed approval/resume intent unchanged, and
uses common recovered apply, receipt aggregation and Result publication.
The observation-only apply path rejects a remaining Ready member before any
target refresh, approval or dispatch binder. It never turns reconciliation
into permission to send an unattempted member. A still-unknown response keeps
the capture and reconciliation state; observation failures do not reclassify
the Run. Successful aggregation uses the journal's existing compare-and-swap
transition from `needs_reconciliation`, not a new `resuming` state or intent.
An unknown execution without an Effect continuation is not handled by this
Table observation path.

Catalog head publication, the original operation's immutable commit record and
storage reservation transfer form one durable Catalog transaction. The record
binds request CID, old/new generation, schema, mapping and the complete owned
file inventory. This is a provider obligation not automatically supplied by
stock PyIceberg SQL Catalog calls. A commit implementation must demonstrate the
transaction and filesystem durability; a post-commit ledger write alone leaves
an uncertainty window. The Effect Ledger receives the typed receipt afterward.
Failure to retain/confirm that receipt remains pending and reconciles the same
Catalog operation, without another write.

Uncertainty reserves all potentially published files and operation evidence.
Only authoritative noncommit evidence permits staged-file reclamation. A missing
operation lookup, disconnected Catalog or changed current head is insufficient.
Reclamation is confined to the exact owned inventory and existing cleanup owner;
failed cleanup retains responsibility and capacity until retry succeeds. No
path-based scan adopts unknown files or follows symlinks outside the warehouse.

Persistent storage has finite configured byte, file and operation-record limits.
Reservation includes metadata/manifests, data, presence companions, staging and
retained generations, plus concurrent uncertain operations. Exhaustion rejects a
new commit without deleting live or uncertain files. Old-generation automatic GC
is deferred. Read acquisition pins an immutable generation; later replace does
not change an acquired reader. Run/Result release releases only temporary input
and read ownership, never the Table or its live files. Original commit records
remain available after later commits and Run release within the configured
durable storage installation.

The optional local I/O bridge resolves a read selector containing the installed
Catalog, namespace/name, Table UUID and schema CID. It reads the Catalog head
and original publication record in one database snapshot, validates the
immutable metadata and saved storage mapping, and returns that generation's
receipt, mapping and canonical logical schema wire. Subsequent reads use this
frozen generation, not a later
head. Unknown tables, mismatched UUID/schema and missing publication records
are refusals, not empty tables or reconstructed records. This read resolution
is not reconciliation of an uncertain Effect: the original-operation lookup
remains separate. The installed Source caller must check current read authority
before and after I/O and admit decoded rows through the common presence-aware
Relation owner; this physical primitive alone is not public Source acceptance.

The installed Table row adapter restores SourceViews from the exact saved
logical schema and an explicit Table selector, without Catalog I/O during
installation or Check. Selector identity preserves namespace/name data bytes;
configuration text normalization cannot alias different physical Tables. The
existing installed row Source owner checks current authority before acquisition
and again after metadata and data I/O, admits the entire decoded input through
its presence-aware row contract, and owns page/capture accounting and cleanup.
A read freezes one generation before subsequent data access. Its close releases
only temporary acquisition custody, never Catalog-owned files. The optional Host
installation loader supplies its trusted local Site/read-approval boundary;
this adapter does not issue authority or implement another scheduler.

The closed `actql-installed-local-table-source/0.1` and
`actql-installed-local-table-effect/0.1` profiles enter the existing generic Host
installation tables. Host configuration, never Program input, selects the
absolute Python path, bounded physical Catalog configuration, logical
connection, account configuration, finite targets and runtime limits. Loading
performs no physical Catalog I/O. Effect installation independently admits its
Check Environment and requires the exact installed Mapping CID and target with
mandatory approval. The existing capture, approval, Effect Ledger and receipt
owners remain the runtime path. Source installation derives its schema from
the saved contract and only admits opaque current read decisions or a
Checkpoint decision for its exact physical target, field subset and principal.

The selected Local installation also binds its reviewed implementation bytes,
not only a Python executable path or a revision label. The existing adapter
import graph and checked Connector asset declaration produce one finite file
inventory shared with packaging. Local observes at most 128 regular files and
16 MiB in total, including its host modules, worker, dependency lock and physical
machine contract. Its installation and target Capability identities include the
content observation CID. The generic Host passes this selected declaration to
the Connector; it does not interpret Iceberg mappings or issue physical proof.

Before preparation, dispatch, original-operation observation, read and cleanup,
the Local bridge verifies that this installed content still matches. Recovered
continuations must match the exact installation binding and approved target
Capability. Changes do not select a replacement candidate, send a new request,
or erase the original Ledger/capture and potential published-file responsibility.
The Host must keep installed package files and its Python environment trusted
and immutable while operations run: a content observation is not a sandbox or
an atomic filesystem/executable attestation. Changes to external Python library
bytes behind the same executable path are outside this package inventory; the
Host installs the supplied hashed lock explicitly and governs that environment.

The private IPC reader can enter the caller's original synchronous body backing
after checking an announced length and before allocating the body Buffer,
decoded String or JSON tree. The prepared process captures this entry once.
The Table bridge forwards the same entry with each read or original prepared
write, target inspection, reconciliation and cleanup; it is not serialized in
operation DATA. The entry must complete synchronously and return no value.
It issues no permission, Plan or capacity. Its installing caller must bind the
actual original Request/Run and admit the simultaneous constructor material
before returning. Omitting the optional transport entry preserves the existing
transport behavior but does not establish managed Table backing.

The separate original `bodyReceived` entry receives only the fully arrived
Buffer before UTF8/JSON decoding, including a subsequently refused payload.
An announced length or successful parser return cannot manufacture that
received-byte fact. The original response Buffer is neither copied nor
re-encoded for this observation. The caller must consume each actual RowRun
ticket at its corresponding original observation/page boundary; this transport
entry itself issues no ticket or row and cannot infer a business outcome.
Both synchronous entries use the SAME process callback custody and original
cleanup. An asynchronous received-body result is refused and remains retained
until its original task settles; foreign unjoined results stay pending.
The Table bridge captures the original callbacks outside wire DATA, forwarding
them unchanged through live reads and the original prepared operation.


A refused entry dispatches no body. Its original cause, including immutable
errors and thrown undefined, remains attached to the same process cleanup.
A mistakenly returned task cannot stand in for backing: the existing process
owner keeps that original task pending through process exit and joins its
settlement before reporting cleanup complete. An unjoined foreign task remains
pending. The Table bridge observes the SAME cleanup handle's actual pending
state before publishing its writer-stopped observation. A completed exit wait
or retry is insufficient when that original handle still retains callback or
service duties. Pure preparation refusals before launcher selection have no
physical child; once launch is selected, a missing or pending original cleanup
observation cannot authorize staged-file cleanup. No receipt or successful
response is synthesized from either case. Process exit, capacity admission,
Catalog cleanup and durable outcome
evidence remain separate obligations.

The adapter package carries only the reviewed Python worker modules and pinned
requirements. It carries no virtualenv, Catalog, credential, fixture data or
automatic dependency installer. Python libraries remain an explicit dependency
only of the Host opting into Table I/O. Installing either role is distinct from
completing the packed public create/replace and different-Run read path. The
existing managed identity policy still refuses direct acquisition Result
publication; the initial read path uses acquisition followed by a Compute task
and ordinary Named Result publication rather than weakening that policy.

## Definitive publication conflicts

The physical writer records a validated create-name or expected-generation
conflict as `actql-table-noncommit-receipt/0.1`. The Catalog transaction checks
the exact original operation's committed record first; a return-path error
cannot replace an existing commit with failure. If no commit exists, the
transaction requires that operation's retained allocation, atomically fences
future publication and saves its sealed noncommit receipt. There is at most
one such record per allocation, bounded by the existing operation limit.
Receipt/fence persistence failure remains uncertain. A missing record or an
arbitrary physical error is not a definitive refusal.

The installed bridge retains these physical bytes under the original dispatch.
The common Table projection admits the exact request, Effect, Catalog, schema,
mapping and action-specific reason before the existing row outcome/Receipt
owner can select `failed`. A readonly original-operation lookup can restore a
lost noncommit reply under current evidence authority without sending again.
Cleanup still requires observed physical stop and retains its own fallible
manifest/deletion/reservation responsibility; recording noncommit neither
deletes files nor releases capacity early. Original facts survive cleanup and
later commits independently of current Table head.

## Implementation boundary

The shared operation and logical receipt bind the original checked input,
Catalog, immutable Table identity and generation. The logical receipt includes
the CID of the Connector-validated original physical receipt. Metadata
locations, Iceberg snapshot IDs and field-ID/presence encoding are owned by the
Local Connector contract. The Local MoonBit adapter admits the saved physical
response and projects a separately sealed logical receipt; the common Owner
then checks operation correspondence and the immutable input measurement.
Physical response bytes remain under the existing Ledger and Catalog custody.
Logical and physical receipt CIDs are not interchangeable, and the common
receipt reader does not accept the physical envelope as a compatibility form.

The selected installed Connector supplies `projectCommitResponse` for both live
settlement and original-operation reconciliation. It validates its saved
physical response using its own MoonBit contract before returning the logical
envelope. The common Table connection has no implicit Local/Iceberg fallback;
a missing or failed projection leaves the original response and unresolved
responsibility intact. The Ledger saves the original physical bytes, not the
projected logical envelope. Projection neither authorizes another send nor
replaces the original response during recovery.

The machine contracts and bounded common admission specify the supported
operation and receipt boundaries. A Connector must connect its declared
operation/Carrier combination to the existing writer, capture and Effect
owners; unsupported combinations are refused before staging or dispatch.
SQL/Pipe/CTAS use the same checked action via the Frontend owner, not a second
writer. Public acceptance must cover approval, response loss, process restart,
concurrent replace, later commits, missing/NULL/value, typed empty input and
reading from a different Run after the source Run releases its resources.

The adopted October 1 Table materialization design is retained in the external
workspace review archive. It is the design antecedent, not runtime evidence.


### Original constructor observations on the existing Host port

A selected Table process may request a constructor observation through the
existing `host-request`/`host-reply` continuation, under the original session,
run, sequence and increasing call number. The installed Host fixes its finite
`maxHostCalls` before launch. The private `constructionObserver` is captured
once, must return `undefined` synchronously, and shares the original process's
callback and invalid-task custody. It is mutually exclusive with a separately
selected Host service; it is not a second dispatcher or resource owner.

The worker selects this connection only with the private execute field
`construction_observations: true`. Its original dispatch receives the same
`before_materialization` callback; an omitted field preserves the explicit
physical diagnostic path. A successful continuation is exactly
`{call: originalCall, value: null}`. It carries no capacity, permission,
publication outcome or physical return acknowledgement. A foreign tuple,
repeated call, extra field or non-null value cannot continue construction.
The ordinary hello body remains null; delegated execution-budget handshakes
are still refused.

The installing caller must derive the constructor quantity from the actual
selected geometry and grow its same-parent backing before returning. Merely
selecting this continuation neither quotes nor funds a Catalog, Parquet,
Arrow or output constructor. Received-byte charging and final row admission
remain separate original obligations.

A constructor refusal stops the original child and retains the exact local
cause, including `undefined` or a frozen exception. A returned asynchronous
value refuses admission and remains on the same process cleanup record until
its original settlement. Host stop while waiting for continuation returns no
worker success or material acknowledgement. Only the existing process/capture
retirement path can discharge the corresponding cleanup responsibility.


### Original Parquet and flat-row constructor geometry

For an observed read, the Catalog retains the same open data-file descriptor
through footer, native metadata and Arrow data construction. It observes the
actual footer bytes before `ParquetFile`, preserves both pinned PyArrow native
parser defaults, and additionally bounds each valid string/container by that
same footer wire. The installed upstream header is the independent source for
those two existing dependency defaults; they are not ActQL capacity policy.

The original footer's uncompressed chunk sizes, row count and physical column
count are observed before the Arrow read. Compressed file size cannot stand in
for dictionary-expanded data. The data-file row count must still match its
original Iceberg task; this adds no logical key, ordering or conversion rule.
After the existing field-ID/type/presence checks, the actual flat Arrow Table's
bytes and dimensions are observed before `to_pylist` and the mapped output
row dictionaries. The same values preserve negative zero, exact binary64,
original text and NULL/omission. Typed empty material has zero bytes/rows and
keeps its original physical schema.

These observations are constructor DATA, not a reservation or grant. The Host
must map each one to its same-parent simultaneous input/output/failed-prefix
backing before allowing that call to continue. Earlier Catalog/bootstrap,
metadata and compressed manifest decoding retain their separate before-call
obligations; the later Arrow observation cannot retrospectively fund them.
Explicit physical diagnostics may omit the observer, without establishing
managed preparation or a normal fallback. Invalid physical correspondence
continues through the existing failed-I/O path; it supplies no business
noncommit, success or physical cleanup acknowledgement.

Synchronous frozen-generation reader, not a writer stop observation or publication/cleanup authority. The managed process owner handles actual interruption.
