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

## Operation and publication identity

`actql-table-operation/0.1` binds the saved logical request scope and Effect
identity, installed Catalog identity, exact namespace/name, create/replace
action, expected Table UUID and generation (replace only), captured input
Artifact and logical Relation, schema, data policy and storage mapping. Its
`request_cid` excludes only that root self-field. Repeated statements retain
their distinct checked Effect identities; a table name is not an idempotency
key. Current authority remains a separate prerequisite, never reconstructed
from saved values or refreshed by changing the original request.

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
fields. The common issuer selects consecutive IDs in canonical schema order,
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

Storage mapping issuance consumes the existing completed Relation export
receipt, not adapter-authored schema JSON or an asserted schema CID. It uses
the complete checked schema, including conditional columns that no actual row
contains. The same schema yields the same mapping for empty and nonempty input.
Unsupported declarations and physical-name collisions are refused before
staging. The schema identity preserves logical constraints that are not part of
the physical boolean/double/string discriminator.

The common Host binds a Table request to the exact checked `store` member,
captured local Result Artifact, issued Effect identity and logical request
scope. It checks the request's Artifact, logical Relation, schema, mapping and
effective Data Policy against these owners. Another member's identity, an equal
but foreign captured owner, or a resealed request with substituted input facts
cannot supply that binding. The binding retains the existing owners; it does
not establish a second input-custody or execution owner.

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

The Table input binding is paired with the existing checked captured Preview,
including its exact live source occurrence. A different member, substituted
operation, row-oriented inventory, missing approval requirement or different
generation guard is refused. The retained subject is the complete Effect Set
Preview CID, not the Table name or request CID alone. This binding is not an
approval grant: current installed target validation, permission and approval
decisions, source availability and durable claims remain required at apply.

For process recovery, the same private capture record retains the original
sealed storage mapping and operation for each Table member. A recovered typed
Table view derives the operation from that member's sealed Preview, re-admits
the exact mapping, and matches the original request scope, semantic Result
Artifact, schema, logical Relation, policy and physical source occurrence.
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

Prepared request and captured input are retained by existing owners before any
dispatch. Table staging, metadata publication and Table writes require approval
and current write authority; pre-approval Table writes are zero. Retaining Run
input is not Table publication. Dispatching/Unknown never authorize another
commit. Recovery reads the original operation's durable Catalog evidence under
current read/reconciliation authority and uses existing Effect transitions.

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

## Implementation boundary

The narrow machine contract and bounded common admission below specify the
operation and receipt; they do not claim ordinary Program execution is already
connected. Subsequent units implement the real writer/Catalog transaction, bulk
Effect lowering/application and published Local/HTTPS acceptance. Existing
unsupported-Effect guards stay in place until that full consumer boundary closes.
SQL/Pipe/CTAS use the same checked action via the Frontend owner, not a second
writer. Public acceptance must cover approval, response loss, process restart,
concurrent replace, later commits, missing/NULL/value, typed empty input and
reading from a different Run after the source Run releases its resources.

The adopted October 1 Table materialization design is retained in the external
workspace review archive. It is the design antecedent, not runtime evidence.
