# Committed Result descriptions

`Result.describe(options)` projects retained publication evidence. It does not
sample rows, open the payload, start a delivery attempt, or submit a Program.
An empty Result has the same description semantics as a nonempty Result.

The Client–Host operation is `result-describe`. Its closed request and response
shapes are registered in
[the Client–Host contract](../../spec/contracts/actql-client-host.json).
The recursive column contracts come directly from the existing
`canonical_value_contract` in
[the protocol schemas](../../spec/contracts/actql-protocol-schemas.json).
The SDK contains generated validation and transport code, not a compiler or a
separate type system.

## Identity and column order

The response binds the exact Run reference and Result name to their existing
Program Definition, Result Definition, Result Artifact, and Result schema CIDs.
`columns` contains names and full checked value contracts in Result declaration
order, including nullability, nested fields, numeric precision and scale, and
vector dimensions where applicable. The schema CID identifies the canonical
schema map; canonical map ordering does not replace column declaration order.
The publication exporter preserves the checked occurrence's declaration order
in the existing durable binding's `result_fields`. Payload row keys and the
execution receipt's canonical schema enumeration are unchanged.

Existing immutable bindings are not rewritten. Descriptions use each retained
binding's field order. New exports with a noncanonical declaration order have
different binding and dependent publication CIDs; the canonical schema map and
its CID are unchanged by this presentation-order correction.

The common publication owner checks the index, Manifest, exact durable binding,
Result Definition, and schema body. The SDK checks the requested Run/name/profile
and recomputes the schema, Definition, and serialization contract identities.
An Artifact CID is a reference to the published Artifact, not an access grant.

## Publication, retention and authorization

Only a confirmed publication commit can be described. The installed Host admits
the distinct current description/read and egress permissions once for this
public operation, before protected access. Its trusted internal reads consume
those same immutable facts instead of evaluating the same tuple again. Actual
application callbacks or relevant authorization changes retain their current
checks; a new public operation observes current Deny independently. Unavailable
authority denies access. Unpublished, publication-unknown, and unauthorized
Results do not expose a description through this operation.

The same-owner Manifest issuer retains the exact immutable canonical Artifact
children already admitted by the publication owner. It measures the original
complete body under the existing bounds, admits only the small root/key skeleton,
and inserts those children without serializing and reparsing their subtrees.
Registered shape, complete identity and relationship checks remain; known child
identity uses only that same private canonical value and its measured limits.
Generic admitted Result-name spellings retain their original key normalization
and diagnostic order. Manifest wire and CID do not change.

Nested identity admission first checks the private Artifact original at the
same Result position. The issuer supplies those originals in its emitted order,
so the matching pass needs one comparison per child in that case. A position
miss retains the existing search and full admission fallback, including when
key normalization changes the order. Every match still requires the exact
immutable child and the current wire, node and depth bounds. This does not
change the remaining Root validation traversals or establish a whole-issuer
time bound.

Before emission, the issuer indexes the supplied Artifact contracts by their
Result Definition CID and tracks original Result names in an invocation-local
table. A duplicate Artifact binding remains ambiguous rather than selecting a
first or last original. Definitions still pass the same checks in their
original order, preserving duplicate-name, missing-binding and wrong-contract
diagnostics. Neither table changes emitted ordering or canonical names. Their
entries are bounded by the supplied inventories; they are temporary lookup
state, not a persistent cache, authorization or resource-funding evidence.

Subsequent Root checks still bind the Run, Invocation, complete Definition and
Artifact inventories, names and references. When a nested value is the exact
same immutable admitted Artifact value and fits the current bounds, that
relationship needs no second canonical stream comparison. A separately admitted
Manifest, missing usage, changed child or tighter bound keeps the original full
comparison and refusal path. String admission is unchanged. These are private
representation facts, not current authorization, a claim, or a durability ACK;
physical readers, lifetime and publication cleanup retain their own duties.

The physical Store returns retained immutable metadata without opening or
rehashing a payload generation. Existing Manifest read grants authorize and
account for the metadata response. Existing retention owners validate metadata
deadlines and any exact-base retention extension. An expired or deleted payload
does not prevent description while metadata remains retained and currently
authorized. Description success is not a payload-read guarantee and does not
change Result availability or the historical Run outcome. Expired or deleted
metadata is not reconstructed by recomputing the Run.

One semantic metadata acquisition hashes the bytes read from its original FD
and checks the digest-named object path against that same unchanged hard-linked
allocation. It does not reopen and rehash the identical allocation as another
validation boundary. The reader retains its actual close duty, size/identity
checks and bounded backing. Later acquisitions validate their new original;
no persistent successful-digest cache hides changed bytes.

One serialized Store publication commit retains the selected semantic metadata
observations for its inventory, evidence and binding phases. The same private
bytes and digest are consumed after their original read FD has closed, instead
of reopening and rehashing the unchanged allocation at each internal phase.
The selected buffers overlap for that operation and remain subject to the
existing object/input bounds and allocation failure handling. They are not
returned by the public mutable-byte API or retained as a Store-wide success or
authorization cache. A distinct operation acquires its own originals. Native
delivery metadata keeps its actual database original; payload holdings, current
authorization, durable publication/claim transitions and pending cleanup retain
their separate responsibilities and real acknowledgements.

Publication setup can persist its finite immutable contract inventory through
the existing Store's grouped contract operation. It owns the supplied name/wire
pairs before callbacks, admits each distinct body, and applies the Store's
object-count, per-body and aggregate storage limits before physical acquisition.
Legacy/raw file-backed groups retain the existing physical batch protocol.
Every new body retains its actual file write, synchronization and original
close. The group shares the object-directory and semantic-link-directory
acknowledgements; no caller receives provisional per-contract durability.
A failed write or directory acknowledgement retains the same cleanup duty,
without issuing a publication, a replacement object or a capacity refill.
The public Index still has its independent logical commit. Stores without the
optional group operation retain the existing per-contract protocol; a failed
group never falls back to repeating individual writes. Empty inventories do no
persistence work. Wire identities and the existing physical file layout remain
unchanged.

The same-original publication operation stores new immutable metadata bodies in
the existing Store SQLite database, with one actual `FULL`/`fullfsync` transaction
for the group. It does not also create per-body object files and semantic hard
links. Existing file originals, schemas and the existing
attempt/progress file protocols keep their original representation. A repeated
raw write of an already native body uses that same native original, not a second
physical copy. Public contract wires, identities and publication authorization
are unchanged; the public Index retains its separate logical commit.

For a native publication attempt, that separate Index commit can use the same
Store database: its complete key/CID, immutable body, inventory, material owners
and quota delta share one actual FULL/fullfsync transaction after payload
custody is retained. The final transaction checks the original committing
record and whole-Run fence. It does not also create filesystem Index aliases.
Existing file-backed Indexes keep their actual file/directory ACK path.
Selected reads admit the actual body and full tuple; cold native confirmation
uses the same original write, never row visibility as an ACK. Unknown storage
and payload cleanup retain their original duties without replaying execution.

The database persists native body count and UTF-8 bytes in the same transaction
as insertion/removal. These consume the same Store object and byte limits as
file bodies and pending reservations; they are not SQLite heap or disk extent
claims. Opening reads the bounded usage singleton, not every historical body.
Only a supported older private format can first adopt the additive tables;
missing adopted tables/counters refuse instead of resetting usage. A lost COMMIT
reply retains the exact original metadata group and its capacity reservation.
Only a real same-database confirmation write can settle that same duty; a visible
row is not an ACK, and no Run, claim, grant or protected action is replayed.

The private metadata inventory distinguishes native bodies from physical files.
Native entries retain their semantic identity, complete-body digest and byte
count, never a fabricated file path or file ACK. Last-reference retirement uses
the same database transaction and decrements usage once, including idempotent
same-original recovery after Unknown. Shared bodies stay live for other actual
publication inventories. Payload files and native database close retain their
separate original acknowledgements.

That setup can pass the original immutable contracts from the same publication
control directly to its Store. The existing control retains the actual issuer's
captured wire/node/depth bounds with each original. Compatible consumer bounds
reuse those canonical facts without another parse, encoding or identity hash.
Foreign controls, copies, raw wires, unavailable original bounds or stricter
unsupported bounds use the normal admission path; none is treated as permission.
The conservative bound on JSON nodes uses the canonical wire's UTF-16 length,
and its UTF-8 byte upper is bounded by three bytes per code unit and the issuer's
checked byte ceiling. These are pure immutable representation facts, not a
Store-wide Allow or successful-disk-read cache. Selected storage reads still admit
their actual bytes, and physical writes, durability, current authority and
cleanup retain their independent checks and original acknowledgements.

The Store's incoming publication-attempt and progress-record operations admit
and interpret the supplied contract once, then pass those same private facts
to physical persistence. They do not call raw-contract admission again merely
because storage is an internal helper. Public raw writes still admit each
supplied wire, and each new operation performs its own admission. Selected
previous records, transition/sequence conflicts, semantic identity and actual
file/native writes, synchronization, alias custody and cleanup keep their
existing checks. No admitted-object argument or successful-read cache is
exposed to callers, and this reuse supplies no permission or durability ACK.

New publication attempts and progress records use the existing exclusively
owned Store SQLite database. The admitted immutable body, object/byte quota
change and indexed attempt or sequence locator commit in one FULL/fullfsync
transaction. Preparing a body alone does not advance progress. The sequence
mutation compares the exact selected predecessor inside that transaction;
the locator is private persistence metadata, not authorization or a second
publication authority. Selected reads admit the referenced body and check its
attempt and sequence. Ordinary reads do not scan unrelated attempts.

The existing publication caller can supply its immutable setup bodies and
initial attempt together through the Store's optional `beginPublicationAttempt`
operation. Native setup admits the bounded originals once and commits their
bodies, complete quota change and attempt locator in the same transaction.
The caller marks both setup duties complete only after that real COMMIT;
preparing and committing records remain later independent transitions.
The original complete group and reservations remain owned on a lost reply.
For an unknown native setup outcome, the caller may confirm that same cleanup
once, then select the exact immutable bodies and installed attempt locator from
the same Store before continuing its original publication progression. Pending
cleanup, a missing locator, mismatched bodies or failed confirmation retains
the original Unknown; none invokes setup again or repeats Effect work. Healthy
setup adds no confirmation reads.

An unknown Index installation can retain the same native storage writer before
commit reconciliation can read through the Store. The existing publication
failure path may make one bounded attempt through that original cleanup and
confirmation handle before lookup, using its captured methods and receiver.
This also preserves the original payload custody; it neither repeats the
publication request nor issues another Index, attempt, computation or Effect.
A still-pending or failed confirmation retains the original failure and duty.
Only the actual subsequent lookup and unchanged complete commit validation can
resolve the publication. Generic and legacy failures retain their existing
lookup path, and healthy publication adds no cleanup attempt or read. The same
connection remains available to the retained Unknown reconciliation holder;
retirement, storage acknowledgement and public publication stay separate.
An independently adopted file attempt retains its file progress and actual
acknowledgements. A Store without this optional operation keeps the separate
setup operations; an explicit refusal never falls back to another write.

No duplicate object file, semantic alias or attempt-directory ACK is required
for those native originals. Independently adopted file originals keep their
file protocol and actual ACKs; a native attempt may reference an existing
file record without replacing or refunding that physical holding. Payload and
public Index writes retain their separate real durability and cleanup duties.
Lost COMMIT replies retain the same bodies, capacity reservation and sequence
mutation for an idempotent same-database confirmation, never a Run replay.
Store close attempts that retained failed writer's original confirmation before
checking its reserved capacity. An unavailable confirmation remains pending;
independent live payloads, readers and other cleanup duties still refuse close.
Once a completed Effect receipt enters publication, its existing completed
Result owner retains the exact publication failure and any original cleanup
receiver. Captured and recovered Site callers propagate that failure instead
of issuing another interrupted-apply completion. This does not mark the Run
committed or acknowledge storage; the original cleanup confirms only its own
physical mutation, with current authority and Run reconciliation still separate.
If an append loses its native progress COMMIT reply, the same publication call
may confirm that exact mutation once through its retained cleanup receiver.
It continues only after the original cleanup retires and the same Store admits
the complete expected latest record. The issued record, Receipt and attempt
are reused; no Effect dispatch or publication reissue occurs. Failed or pending
confirmation, a missing record, or any differing record retains the original
failure. Healthy appends perform no confirming reread.
Run metadata retirement selects its indexed attempts and records, removes
their actual bodies, and retires their locators with the existing Run fence.

The private database format adds the attempt/sequence tables in one bounded
schema transition. Existing file progress is not imported or re-admitted on
every open. Missing adopted tables or index refuse rather than recreating
progress or treating missing coverage as an absent publication.

Preparing a Result schema that already has an immutable semantic owner acquires
and validates that schema's selected file original, then retains a holder in the
same Store. It does not create another allocation or rewrite durable preparation
markers for bytes that this preparation cannot reclaim. The holder still blocks
Store close and same-Store metadata reclamation until release or adoption. Each
distinct preparation reads its own original, and a failed reader close keeps its
same cleanup duty. A newly created schema retains the existing durable marker,
generation checks and crash-reclamation protocol. Existing schema ownership is
not replaced or refunded when the temporary holder retires.
An unsettled physical writer is not an established durable schema owner merely
because its final link is visible; that case keeps the original write/ACK and
pending-cleanup protocol before schema preparation can succeed.

Within that commit, the admitted Index body is persisted directly rather than
sent through the public raw-contract admission again. Verified Binding facts
provide their original physical and schema identities to inventory construction
and same-identity replay checks. A different stored Binding still receives its
own selected read. No public raw input check, physical payload verification,
directory acknowledgement or next-operation acquisition is replaced by these
internal facts.

The Effect evidence inspection returns its verified Binding facts to the same
serialized commit. Inventory construction consumes those facts without a second
payload acquisition, hash or schema validation. The commit obtains them from
its own internal inspection, never from a caller-supplied inspection result.
A separate stored-evidence inspection still acquires and validates its originals;
these facts do not authorize an Effect or replace any durable acknowledgement.

Known file-backed Index and Result-schema reads select their file representation
directly; they do not first query the native delivery-metadata tables. The
selected file still supplies its real bounded bytes, inode/digest checks and
close duty. Generic semantic reads and supported native publication/delivery
families use selected database rows with legacy file fallback.

A successful fresh object seal closes its original writer, installs and
acknowledges the final object name, and keeps that same allocation fully
charged in the Store. Removing its private staging alias is not a second
durable publication or capacity refund. After that success, the alias is
unlinked without another staging-directory barrier; exclusive opening recovery
removes any resurrected temporary alias. An existing-object duplicate has a
different temporary allocation, and cancellation or any failed seal keeps the
original staging-unlink acknowledgement before releasing its reservation.
Failed unlink still retains the same writer/reservation and retry path. No
payload sync, final-name ACK, actual close or pending custody is waived.

Typed publication evidence selects its storage representation before the commit's
generic inventory traversal. The traversal reuses those acquired originals;
it does not repeat the same selected row/file admission merely because it
encountered the CID again. The admitted Index also has its known
file representation. Additional untyped inventory still receives its original
generic lookup, and missing originals refuse before publication becomes visible.

## Delivery profile and bounds

`format` defaults to `jsonl`. The current public delivery owner admits `json`,
`jsonl`, and `csv`; other formats are rejected explicitly. The returned
`serialization` describes the requested delivery contract (`actql-jsonl/0.1`,
for example), not the internal storage codec. Describing a profile does not
change the SDK row reader's format or promise every value is losslessly readable
through a different consumer.

The whole response, including its Run reference, is bounded by UTF-8 JSON wire
bytes, structural nodes, and structural depth. Defaults and hard ceilings are
1,048,576 bytes, 10,000 nodes, and depth 64. Callers may tighten each ceiling.
Containers and scalar values count as nodes; object keys count as additional
nodes. Root depth is one. Oversized responses fail without truncating columns or
contracts. These limits do not constitute a general process-memory guarantee.
Aborting description stops that metadata request and never cancels the Run.

Confirmed denial, including an absent or reclaimed public index, is
`ResultAccessDenied`. Expired metadata or missing evidence behind a retained
index is `ResultDescriptionUnavailable`; caller bounds produce
`ResultDescriptionTooLarge`. Unsupported caller formats produce
`UnsupportedResultDescriptionFormat`. Malformed or mismatched Host responses
produce `InvalidHostResultDescription`. Transport failures remain read failures;
the SDK never converts description into a new submit.

## Clock commit and current authorization

A returned `sampleTrustedClock` value is durably accepted, not merely a wall
clock observation. Local Store samples after reading the same serialized floor.
Each public Result operation accepts one durable clock sample. Its existing
owned request retains that floor through internal authorization stages and
trusted Store reads; getters and awaits do not commit another observation.
Synchronous time and expiry checks still reject rollback or expiration before
dispatch and after physical I/O or application callbacks. A new public operation
accepts its own observation. Generic explicit-observation Stores use the same
operation boundary without weakening their original commit/Unknown handling.

Local clock records keep their original names. First creation, legacy-record
replacement and size changes commit both file data and the directory entry.
Equal-size updates of an already confirmed checksummed record keep the same
inode and fsync its data before acknowledgment; they change no directory entry.
A torn record refuses instead of selecting an older floor. Failed fsync or
close is not acceptance, and Store retirement waits for the original operation
and any retained failed-close duty. Existing two-field clock records remain
readable; configurations too small for the checksum use atomic replacement.

### Output callback Account observations

One Result operation retains its exact principal, namespace, scope, Run, name
and purpose in the existing owned request. Pure internal stages, trusted Store
reads and FFI exchanges consume that request's admitted Account judgment; they
do not create another authorization frame. Run-read and named-Result-read
remain distinct permissions, and a new public operation observes current Deny.

An application output sink can reenter or change the installed Account during
`write` or `finish`. The existing delivery state counts those actual callbacks.
Before another protected dispatch or successful receipt, Local authorization
observes the current Account at that boundary. If its immutable original is
unchanged, the operation reuses its one evaluation instead of repeating
admission, parsing, hashing or policy evaluation. Changed, missing, rejected or
foreign Account state cannot reuse the prior Allow. This count is neither a
permission nor a durable receipt, and does not change the original delivery
claim, quota, byte exposure, COMMIT Unknown, non-resend or cleanup duties.

### Bounded installed READ workspace and physical writes

An installed Local Result READ admits one original ClientRequestPreparation
using the installation's existing requestMemory policy and physical supplier.
It does not borrow the retired producing Run, initialization spare capacity or
a Host-wide RAM pool. Concurrent reads of the same Result retain distinct
Request originals. The existing fixed Common controls cover this exclusive
READ phase. After the Store supplies metadata, that same capacity reserves its
retained schema and subsequent frame, row and output overlap before their
constructors. A refused reservation remains a failed READ, without falling
back to an unfunded delivery. The Store's preceding bounded metadata reads and
schema admission are not established as numerically funded by this later
reservation; their original construction accounting remains a separate duty.

The selected output window is bounded by actual payload, frame and wire
limits and the original Resource ledger's available retention and execution
capacity. Raw-row demand grows geometrically before parse and serialization;
rows within the acquired high-water use local counters. Staged immutable text
is flushed before growth. A larger row may reduce the output window or use a
single funded write; neither path reserves a whole Result or assumes a managed
heap allocation corresponds exactly to the Common representation tariff.

Several canonical rows may share one physical sink write. Their concatenated
bytes, digest and confirmed prefix remain unchanged. Each actual write and
finish retains the original current Account, grant, expiry, cancellation and
exposure checks. A callback can change authority before the next protected
write; there is no authorization cache spanning that callback. Outgoing byte
backing is not reused while a callback can retain it.

The READ owner retires only after delivery and its original physical-reader
and terminal-record cleanup duties have settled. A completed record alone
cannot release pending reader custody; a throwing or unknown cleanup status
keeps the same parent retained. Completed entries leave the owner map. Raw or
manual services without an installed workspace retain their one-row route.
This resource connection does not replace the original claim, receipt,
durability, non-resend or cleanup owners.

### Selected publication metadata observation

The initial Result resolution already acquires and admits one selected Index
and its exact inventory from the same Store. Description evidence and initial
retention lookup consume that frozen publication pair once instead of opening,
hashing and admitting the same Index again in a trusted nested metadata read.
The existing Store keeps the private association with that returned original;
copied, foreign, wrong-Run or already-consumed pairs refuse. Explicit invalid
input never becomes the omitted legacy path, which still acquires its own
selected publication independently.

The pair retains immutable facts, not permission, a Result delivery claim or a
new durability acknowledgement. Same-Store metadata retirement invalidates it
through the existing indexed Run fence. Binding, schema, payload and retention
originals keep their existing validation and cleanup. Final response and actual
delivery head checks remain after authorization or uncontrolled callbacks; the
payload reader does not consume this preliminary observation. A new public
operation acquires its own pair and detects changed or missing selected bytes.
Weak-key retention adds no Store-wide successful-read or authorization cache.

### Captured computation fact lifetime

The completed Effect-free capture may retain its original typed computation
facts through the same publication. The private runtime association belongs to
the exact captured wrapper and original preparation, not an externally supplied
Boolean or an authorization cache. Chain and commit checks still validate their
selected original contracts, ordered inventories and supported bounds. Restored,
foreign, changed or unsupported tighter inputs use full validation; new Result,
Binding, request, attempt, Index, current permission and CAS checks remain.

The optional internal `retireCapturedComputation(capturedRun)` operation releases
only that preparation's managed aliases. The completed caller retires a capture
cancelled before publication entry; after entry, publication owns the original
retirement method and receiver. Ordinary terminal success or failure retires it
once. A publication Unknown instead transfers it to the existing reconciliation
handle, retaining the same semantic checks through failed and pending retries.
The retry flight is installed before any original callback can reenter.

A finished retry is not necessarily settled cleanup. Only resolved reconciliation
with the same upstream non-pending observation retires the fact and clears the
reconciliation/retirement closures. Status reads, timeouts, process exit and a
pending upstream do not. Physical payload/Source/native/FD duties retain their
existing independent cleanup and ACKs; this alias retirement supplies none.
If the original managed cancel fails, the Unknown keeps its retirement pending
and retries only that same cancel after resolution, without another semantic
reconciliation. A terminal failure and a retirement failure remain distinct
causes; neither is converted into a physical cleanup acknowledgement.

## Stored publication validation reuse

The stored-publication loader creates its dependency inventories privately and
fully validates their contracts, identities and relationships before exposing
a read view. If observed-commit confirmation selects that view's exact original
request, attempt and index, the same owner consumes the completed validation in
one bounded step. The observed child, workspace admission and explicit release
remain separate. Caller-borrowed inventories, copied contracts and changed
observations retain the complete validator. This ownership provenance contains
no permission or physical-current fact; the Host still authenticates and fences
the actual selected rows and retains their loans through response cleanup.

## Ordered-row frame backing

The existing frame Owner admits the total encoded-byte bound and per-row bound
separately. Its private row buffer initializes only the smaller of those two
bounds: every input chunk passes the total-byte guard before any row byte is
written. The configured per-row guard, accepted wire, error precedence and
chunk/depth/row-count checks remain unchanged. In particular, a small payload
cannot turn an invalid configured limit into a valid one. These initialized
slots are managed parser backing, not a physical memory reservation or cleanup
acknowledgement.

## Completed encoder document parsing

A completed encoder document retains its immutable JSON text and exact emitted
UTF-8 byte count. Resumable source parsing may reuse that original Unicode
preflight when the document fits the requested byte bound. It still runs the
same grammar, key normalization, duplicate, node/depth, and cancellation path;
a tighter byte bound or a raw text input retains the original incremental
preflight. Callers that retain a completed writer document may use this
boundary without carrying authority, currentness, or cleanup acknowledgment.
The parser's work quantum remains unchanged; typed Effect Context construction
below no longer needs an outer document parse.

## Retained Effect Context material


The Effect Context issuer constructs its complete canonical material within
the existing canonical admission owner. Ordered keys, scalar text and each
original immutable child pass through the same bounded measuring writer.
Container backing arrays remain private until complete admission, then become
the immutable result without an outer text parse or another decoded tree.
Repeated child occurrences still count toward the complete byte, node and
depth limits; retaining a child does not retain an Allow or physical fact.

The dependency inventory remains a separately admitted wire envelope. Its
actual canonical result is retained after that admission. The complete Context
identity is still computed by the original bounded canonical hash traversal.
Failure and cancellation discard only construction references and continuations,
not the caller's snapshots, readers, physical holdings or cleanup duties.

The Captured Run issuer also retains the original admitted Receipt as an
immutable child. The computation validator may establish that child's complete
wire correspondence from exact object identity and the Receipt's original
final-encoder byte, node and depth measurements. A restored or different child,
missing measurements or tighter limits uses the full bounded wire comparison.
All preceding relation checks, the complete Context identity hash, Result rows
and remaining evidence checks still run. This correspondence supplies no
permission, current observation, durability or physical cleanup acknowledgement.

The stored publication loader retains the selected Index's just-completed
admission when its private caller supplies the same original wire and measured
limits still fit. Raw input byte accounting and physical current fences remain
unchanged. Different wire, contract names or unavailable measurements use full
admission. This avoids reconstructing one immutable Index; it does not retain
a Store observation or replace the first complete publication-chain validation.

## Bounded evidence comparisons

Exact evidence-to-wire comparison uses the existing bounded encoder with a
comparison sink. Every emitted scalar, escape, structural transition and
byte/node/depth charge is still processed; a mismatch is retained until complete
encoding finishes, so it cannot hide an invalid tail or exceeded limit. The
sink compares against the caller's immutable expected text without allocating
and draining provisional text fragments. It exposes neither serialized output
nor a digest. Publication comparison keeps its existing workspace admission,
incremental emitter quantum and cancellation/cleanup owner. Pair comparisons
and full identity hashing retain their separate existing sinks.


## Compiler reader continuation

Fresh task compilation passes the exact immutable graph and execution-material
reader inputs through its existing Executable Plan holder. The continuation
consumes and clears those extra references before fallible work; completed and
refused compilation do not retain the additional trees. Reuse requires the
original complete Plan wire and the issuer's byte, node and depth limits; graph
reuse additionally requires the same prepared owner and exact graph wire. A
tighter request or different input follows the complete prior reader. The
selection projection still checks its original nonempty array and hashes its
complete canonical body. This continuation neither admits external wire nor
supplies current authority, physical availability, execution or cleanup ACK.

Standalone Plan projections and the Values compilation path discard these
continuation-only references before returning. They retain the original wire,
identity and compilation material without keeping unused reader trees alive.

## Writer startup failure custody

The existing object writer observes its startup Promise rejection immediately,
because the payload reader can yield before issuing its first append, seal or
cancel. That observer does not replace the original Promise or its failure.
Later operations retain the existing closed-writer and startup-failure results,
including primitive thrown values. Failed open still releases its original
reservation once. Successful open, pending FD close, custody and cancellation
retain their existing physical acknowledgement requirements.
