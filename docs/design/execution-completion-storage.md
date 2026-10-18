# Completion and physical Relation storage

Execution success and physical layout have separate responsibilities. The
opaque completed sequence retains the exact prepared owner, selected contracts,
Parameter binding and upstream completion anchors. Its private store retains
ordinary row tables, numeric-column tables or admitted-value tables. Neither storage
construction nor equal values establish successful execution.

These representations enter the same ordered driver and final success
constructor. A failure clears invocation-local retained outputs; no completed
handle is returned. Completion and producer admission contain no expression
frame, continuation or scheduling API. Changing synchronous expression
scheduling does not change this boundary.

## Task output authority

`CapturedDAG` owns one task-indexed output slot. A committed slot contains a
typed materialized or managed reference; the variant selects the correct access
surface but does not create another success ledger. Only the common output
commit may attach the graph holding, expose producer readiness, clear completed
input ownership and advance the graph generation.

Execution lifecycle is independent of the output representation. Cancellation,
native settlement, disposal, retention release and physical reclamation use one
common lifecycle interface. These facts remain separate:

1. the operation stopped;
2. validation and required evidence succeeded;
3. a retained holding was admitted;
4. the task output was committed;
5. a consumer was admitted;
6. the holding was released and reclamation was confirmed.

A materializing implementation returns its exact typed output to the common
completion boundary. It receives no task-publication authority. A managed
implementation returns its scoped completion evidence and material reference to
the same authority. Resident output is bound to its verified relation before
the slot is committed, without converting or re-importing the relation.

Both managed and materializing preparation use
`connector_sdk.ExecutionLifecycleOperations` directly. There is no duplicate
managed lifecycle type or conversion adapter. Implementations use lifecycle-only
preparation and typed completion entry points; neither interface grants an
implementation authority to publish a task output independently.

The unified boundary adds no requirement to serialize rows, compute a logical
CID, hash a physical body or rescan an already verified representation.
Materialized, file-backed and resident representations retain their existing
typed access and identity rules. Program publication remains a later, separate
commit and does not become part of task completion.

## Producer admission

Binding checks the producer pipeline, bound preparation and target. Receiver
admission checks selected contracts and input obligations before importing data.
Logical input charging reads every row before projection, regardless of buffer
sharing. The adopted physical view has receiver-owned metadata while its
completion anchor retains the actual producer and original buffers.

An integration can narrow a successful output's future admission through
`bind_live_completed_input`. This shares the original storage and metadata and
combines the original completion predicate with an additional synchronous live
condition. It cannot create success from rows or replace the original condition.
Observation adapters install exact issuer/attempt/observation verification here.
An existing binding or producer read does not freeze that condition: new read
preparation, import and consumer execution still check it. Independently
completed consumers retain their own successful results after upstream revocation.

Each successful producer binding has a private immutable process-local identity.
Fixed-input completions record those identities by receiving port, separately
from their physical storage anchors. `completed_output_matches_inputs` checks
the exact bound owner, all receiving ports and those binding identities; equal
rows, schemas or CIDs cannot substitute for a different binding. Rebuilding a
read view of the same binding preserves that identity. The identities themselves
hold no row buffers or upstream liveness callbacks.

Local execution records the admitted producer bindings. A trusted external
Compute port receives its exact fixed inputs at preparation and snapshots only
their identities; its installed verifier remains responsible for the actual
input/attempt/transport relationship and live admission before completion.
Acquisition ports do not claim fixed-input provenance. Checking an independently
completed result's input affinity does not require its upstream to remain live;
the result's own liveness and retention still apply. No identity wire domain or
logical charging rule is changed by these private references.

Row storage remains the default. A typed producer selects the mixed-storage
adapter before execution. This is representation dispatch, not error recovery:
neither exhausted budgets nor expression failures retry a different strategy.

## Numeric columns and conversion

The private typed representation retains numeric and validity buffers, names,
an explicit row count and optional composed selection indices. Zero columns
do not imply zero rows. No mutable buffer accessor or public disposal operation
is exposed. Public cell observation returns the existing immutable Value form.

Projection uses the existing checked row-body evaluator and a numeric-column
sink. A temporary projected row may exist, but no complete output row matrix
is retained. Index operations use the existing comparison and selection kernels;
their physical adapter composes indices against shared buffers. This does not
introduce ordering inference or change tie handling.

Admitted-value tables use a separate projection sink, not the numeric sink.
The same checked evaluator establishes column selection, aliases, logical
charging and failure order. The sink retains the selected immutable admitted
values by reference, reserving the destination reference arrays before their
construction. It does not re-admit values or convert text, decimal or temporal
payloads to numbers. Empty inputs retain their checked output names. These
tables already contain row reference arrays; preserving them is not a claim of
columnar execution or allocation-free projection.

Non-projection expression bodies use the existing bounded row output builder.
This is the explicit conversion boundary for consumers without a typed output
builder: the input remains readable in its current representation, and only
the output becomes row storage. The shared evaluator charges construction,
retention and values; there is no speculative conversion followed by fallback.

## Lifetime and resource accounting

An opaque `ProducerRead` can expose the immutable receiving schema and cells of
an exactly bound completed producer to a physical input adapter. Preparation
checks the receiver by reference identity, resolves the already checked input
projection to retained source columns, and bounds column/name traversal before
building the index map. It retains the bound upstream output and does not copy
rows, reconstruct ownership, or expose mutable storage. Such a view is not
receiving admission, a successful Compute, or a logical accounting credit;
execution and transfer still enforce their own applicable budgets.

Temporary numeric buffers and index copies are reserved before allocation and
charged to operation work. Common table reservations remain in force. Mixed
stores additionally reserve the full numeric/validity backing capacity and
selection indices, even if the visible selection is small. This is conservative
per-handle accounting; sharing does not reduce logical occurrences or silently
discount a receiver's retention ceiling.

Container/element limits, logical value bytes and process RSS are different
quantities. References keep necessary buffers alive; dropping a user handle
does not promise immediate allocator or GC release. Multiple consumers have
independent invocation budgets and cannot invalidate an upstream completion.

This boundary is not whole-Program admission, Result publication, Arrow support,
general vectorization or a change to the default physical layout.

## Generated Content original storage correspondence

The installed serialization family keeps the exact candidate, issued checked
Reference and confirmed physical holding returned by its existing Store issuance
boundary. This is one generation's retained reference, not a wire/CID index.
Its private consumer projection uses the Common original-reference matcher and
checks the same generation's availability again after synchronous callbacks.
An equal envelope from another issuance, a copied consumer view, cancellation
or a retired original consumer cannot select that stored binding.

Successful temporary encoder/writer cleanup does not retire durable generation
Content. An abandoned generation retains its original cleanup duties until the
same Store confirms their retirement; only then is its stored-binding reference
cleared. Saved-input restoration obtains the stored binding from the existing
authenticated evidence, original candidate re-admission and Store confirmation.
It forwards that very issuance to the family without reconstructing it from the
saved Reference wire. Legacy restoration without this original receiver cannot
provide a physical stored binding through the private projection.

Explicit parent close is distinct from successful temporary encoder cleanup.
Even when temporary duties already completed, close first forbids new original
selections. Once those same duties have retired, it drops only the family's
selection alias; durable Store bytes and escaped originals/borrowers keep their
existing custody. The same rule applies when close awaited the original
generation flight and that flight completed temporary cleanup before returning.
Close, cancellation and the cleanup flag are not physical
holding retirement or permission to return another owner's allocation.

The additional family reference and restored-result field keep candidate,
checked Reference, holding metadata and their currentness closures alive with
the existing generation. Per-call selection closures and checked-value aliases
overlap those originals. They remain part of the original Host/Run inventory;
temporary cleanup, promise completion and reference retirement are not GC or a
physical-byte acknowledgement. This correspondence supplies neither a Content
read grant nor a consumer-phase capacity/allocation, physical loan or dispatch
permission. Those must still come from their existing original suppliers.

## Saved installation-publication physical custody

The existing private publication holding admits the exact additional purpose
`installation_publication`. It uses the unchanged `publication-private`
namespace, physical holding format and AEAD preimage, with the actual selected
Store's private evidence key. It is not Run `source_evidence`. Similar names,
prefixes and arbitrary confirmation kinds remain refused.

The Host/Source publication Owner must issue the semantic binding and holding
identity from its admitted original publication and observations. The physical
binding remains `{name, semanticCid, holdingCid, wire}`; accepting that shape is
not semantic admission of a caller-authored body. A path, private mode, digest,
historical UUID or process-local object pair cannot supply authenticated
original-acquisition custody. No signing, Credential or Run-journal key is
borrowed for this purpose.

Cold physical reading requires the actual Store key, authority and selected
holding. Authentication finishes before bytes escape. The consuming publication
Owner must independently admit the exact body, original generation and actual
new installation correspondence before reconstructing new local Catalog
originals. It must then confirm the exact admitted binding and same holding's
directory durability. This is not pointer equality with an old process, provider
rediscovery or permission to publish replacement observations. Replaying the
same selected durable original is distinct from a new publication.

Commit, confirmation and close uncertainty retain the existing holding owner
and its original prepared handles. Retry reconciles that record, not another
metadata acquisition or a replacement preparation. Store authentication proves
custody of the encrypted body, not the truth of arbitrary metadata or a grant
for current acquisition, Credential use, egress, Content, Model or Effects.

Before use, the existing installation phase must cover the key copy, encoded
body and AAD, native crypto context, nonce/tag/ciphertext and Base64 envelope,
prepared writer and FD duties, holding record/index, live binding aliases and
overlapping cold ciphertext/plaintext/decoded inventories. Same-Store reuse,
wire ceilings, successful authentication and reference retirement provide no
capacity or cleanup credit. Without the actual semantic, storage and lifetime
suppliers the installed path remains unavailable; this physical port does not
invent them.

The physical Store provides
`observeOriginalInstallationPublicationStorageBinding()` and
`originalInstallationPublicationStorageBindingEvidence(handle)` for this
connection. The first re-reads the exact bounded original Store contract on
one FD, then checks Store availability again before issuing its same
process-local handle. The second checks that handle's identity in this very
Store and returns immutable DATA: `storeContractWire`, `storeAuthorityCid`,
`keyGenerationCid`, and `privateNamespace` (`publication-private`). Copying an
equal handle or using another Store's handle does not restore membership.

These DATA are neither Model RunEvidence nor an installation publication
issuer. The getter is not a fresh asynchronous currentness observation; the
Host must retain the actual factory result and use the observation at its
required current fence. Common owns the separate bounded semantic storage
binding and its identity. No unrelated evidence kind or key purpose is reused.
A failed original contract FD close retains the existing read cleanup handle,
blocks replacement observation and prevents Store retirement until that same
FD acknowledges close. Successful Store ownership retirement drops only its
private observation alias; escaped DATA remain their caller's inventory.

One optional observation record, its handle and immutable four-field DATA,
the two method closures, read/retirement callback and in-flight promise,
bounded contract backing/probe, UTF-8 String, key digest context and escaped
references overlap the installation originals. These are additional Host
phase costs, not a new reservation, zero-byte record or physical cleanup ACK.
## Content physical reader backing

The physical Content consumer fills each at-most-64-KiB piece directly from
the same original FD into one dedicated backing, including repeated short
reads. It does not acquire another piece while the consumer callback is
pending or reuse a previously delivered backing. A truncated final prefix is
a view of that original backing, not a shrink copy; the existing final
size/hash/version checks still refuse the incomplete object. Empty objects
retain stat/hash/close without a data allocation. Growth cannot extend the
original admitted extent. Close failure retains the same FD and close-only
retry, never a replacement read or permission to retire a live holding.

For one such read, the sum of allocated piece payload extents is at most the
original stat size, with each extent at most 65536 bytes. This is a byte-layout
fact, not a whole-phase quote: Buffer/view/control objects, promises, hash
state, metadata and independent verification reads, and all escaped consumer
aliases still overlap. Callback return and losing a local reference are not
physical backing retirement, GC acknowledgement, or capacity credit. The
original Source/installation supplier must cover these components and retain
its loan through actual physical and consumer cleanup.

The mandatory object verifier has a distinct, non-escaping read lifetime.
It reuses one dedicated backing of `min(65536, original_size + 1)` bytes,
including the original overflow sentinel for an empty object. Each positional
read is limited to the remaining admitted extent plus that one probe byte.
The verifier refuses an overflowing read before hashing any bytes from that
read; unchanged size, FD/path identity, modification time and content hash
remain required. Short reads reuse the same backing, with only temporary
subarray views for the synchronous hash update, not another payload copy or
queued read. Verification still owns its original FD independently of the
later Content consumer and retries only that FD's close if it fails.

Its fixed backing extent does not price the FileHandle/native read and hash
state, view/result/control records, or the containing metadata/holding phase.
The original supplier must cover those simultaneous components before the
verification I/O; an accepted hash and a zero pending count are not a new
funding issuer or another Owner's physical cleanup acknowledgement.
