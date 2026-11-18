# Common installed row Source Owner

This package retains the existing checked Source requirement, nominal input
schema, acquisition/attempt, physical reservation, admitted rows, capture evidence
and cleanup responsibility used by provider row adapters. Provider material and
cost candidates alone never issue a captured Source. Exact checked contracts,
original transport verification and retained output must remain available.

`row_acquisition_column_contract` is a read-only projection of the original
checked input contract. A provider can use it for ordinary raw-value admission;
it cannot turn an equal foreign CheckedValue into a nominal original or grant
Source access. The input buffer still checks exact contract identity.

## Interface responsibilities

- Responsibility: Common owns checked row acquisition, attempt/capture evidence,
  keyed/listing semantics and original row lifetime; providers own physical I/O.
- Inputs and outputs: declarations and original QueryRequirements prepare typed
  acquisitions. Original attempts admit charged pages and may issue a live
  capture only after the existing completion and verification checks.
- Identity: requirement, schema/field contracts, RowAttempt, issuer, reservation,
  page ticket and captured input remain nominally bound to the original Owner.
- Ownership: the same RowRun holds admitted input, residual work, retention and
  cleanup. Transferred DAG holdings retain their original task responsibility.
- Synchronization: one-shot page tickets, attempt state and original callbacks
  guard consumption; a copied value or current observation cannot create a Run.
- Failure: typed Source/evidence/consumer/physical failures remain distinct.
  Failed cleanup retains the original holding/reservation and responsibility.
- Cancellation: abort stops logical admission; physical stop and final cleanup
  acknowledgement are separate. Cancellation never authorizes a new attempt.
- Resources: accounted entries reserve on the supplied original Ledger before
  physical reads; received bodies charge actual transfer before decoding, and
  original admitted input/residual/capture retention remains accounted.
- Extension: provider-specific spelling adapts to these existing typed ports;
  no provider equality, independent Ledger or generic retry replaces them.
- Verification: package and consuming query-integration cases exercise nominal
  values, page accounting, keyed/listing profiles, capture and retained cleanup.


### Non-row response charge consumption

`consume_row_run_response_charge` consumes exactly the same outstanding nominal
page-charge ticket of a live Reading attempt when its selected protocol observes
control input instead of rows. It neither increments pages nor admits values,
finishes the scan, creates evidence or acknowledges transport cleanup. The
existing ticket Owner checks original attempt, identity and single consumption;
foreign/stale/repeated tickets retain its ordinary typed refusal/abort behavior.

### Installed response-reader borrow

`check_row_acquisition_original` checks the exact original requirement and
declared view, not equal JSON or CID material. A trusted pure preparation callback
cannot substitute an independently prepared acquisition.

`borrow_row_run_responses` lends an already-begun accounted Direct RowRun once.
It creates no reservation, Run or authorization. Before provider I/O the reader
binds its same physical-stop observer into that RowRun's existing cleanup slot.
The original Host retains finish, capture and close; logical abort does not
erase the observer. Failed stop keeps the same reservation and cleanup debt.
Only confirmed physical retirement permits the reader's aliases to disappear
and the original Owner to release its root.

The [response stream accounting contract](response-stream-interface.md) describes
spending that same attempt before I/O and extending one original page ticket
with actual received chunks. Partial-prefix cancellation does not refund them.
The [Common evidence custody contract](../query_planning/evidence-custody-interface.md)
separates successful-capture cancellation, issuer revocation and retirement of
closed custody while preserving immutable observation DATA.

### Original provider declaration projection

`project_row_declaration` is a typed metadata port for an existing Common
producer's already-verified canonical Catalog, contracts, declared views and
manifest. It copies the metadata containers and keeps the exact supplied view
objects and canonical strings; it does not decode wire, regenerate a neutral
Catalog, validate a caller-computed CID, or issue permission/current/capacity
evidence. Salesforce exposes its projection from its original opaque static or
installed declaration, without a JavaScript entry accepting raw parts.

A new projection of equal canonical parts is not an acquisition's original
view. `check_row_acquisition_original` still requires that exact stored view
and checked requirement. The existing acquisition also checks original Source
evidence; a projection-only requirement lacking it remains refused. The
provider's already-bounded declaration owns the projection's input extent;
this metadata port introduces no generic view-count restriction or normal
numeric-profile adoption.

### Supplementary provider overlap

`start_accounted_provider_row_acquisition` accepts a trusted installation's
`ExecutionCapacity` declaration for the same original acquisition, selected
implementation and target recipe. It checked-adds retained and execution
overlap, including the existing scratch, to the same Ledger's `reserve_attempt`
before attempt construction. Missing/unjustified supply remains unavailable;
declaration construction is not a physical measurement, reservation or grant.
Ordinary and listing-report entries keep their existing selection semantics.
The private Node `clientProgramRowSourceProviderCapacity` translates exact
Int64 amounts through the existing `execution_capacity` DATA validator only;
it does not issue an opaque Owner, reservation or physical-cleanup receipt.

Before any provider page or completion, this profile requires the exact
`RowRunResponseBorrow` cleanup binding above. The trusted installer must bind
the original reader's physical-retirement observer before I/O, not callback
return, cancellation acceptance or Promise resolution. Capture retains provider
backing in the original reservation rather than transferring it to a task;
execution and remaining retention survive evidence generation and pending
cleanup. False retirement keeps the same debt for retry. Only that observer's
confirmed retirement allows original close to settle the same reservation.
After successful settlement the closed RowRun detaches that observer and
provider declaration; repeated close cannot re-enter the retired reader.
No numeric profile or transport implementation follows from this primitive.

The selected ordinary installed Credential provider starts without future-page
transfer prepayment; Table/IPC and other explicit profiles retain their envelope.
Before each serial native request, `ensure_row_run_response_transfer_capacity`
backs that request's selected response bound on the SAME cleanup-bound borrow
and reservation. Received and uncertain bytes plus all outstanding reservations
still consume the original cumulative Ledger limit. The original current/stop
fence precedes this mutation and physical I/O; actual body charging still
precedes projection. An unused remainder is not a refund or another attempt.
Whole-input and other explicitly funded profiles retain their existing envelope.

An installed native decoder may grow this SAME reservation through
`grow_row_run_response_capacity` after its original response is charged and
before projection. The selected native quote owns all prior outputs plus the
current constructor, bounded by the largest actually retained response. Growth
never changes parser limits, attempts, transfer or quantity history. The exact
borrow, bound original cleanup observer and unconsumed page ticket remain
required. A repeated identical peak quote does not repeat Resource current;
real growth has one fenced original current boundary. Refusal retains the same
response/cleanup debt and cannot begin decoding. The response phase and its
constructor correspondence are described in
`adapters/host-node/managed-source-reader.md`.

The existing `ClientInstalledCaptureCapacity` Owner's
`installed_provider_row_capture_capacity` projects these same checked sums
before Run Ledger preparation, retaining the exact acquisition and declaration.
`installed_provider_row_capture_capacity_matches` checks that original pair;
equal quantities or equal requirement CIDs cannot substitute another pair.
The existing finite Ledger ceilings, actual overlap admission and refusals
remain in force. The new projection neither raises them nor proves every
downstream Compute/Effect envelope fits. Listing profile substitution is refused.

The nullable profile reference on every RowPhysical, selected declaration,
reader/observer aliases and transition overlap belong to the original Host
inventory. Returned diagnostics, raw history, ID/cursor indexes, parsed page,
checked rows, output and closures must be covered concurrently by the supplier;
maxPageBytes and transfer counts are not substitutes for that declaration.
Every installed capacity record also has one nullable provider-pair reference;
the selected pair retains the original acquisition and declaration until the
existing planning/capture Owner retires it. No extra reference is free merely
because it aliases an existing object.

### Static Resource identity in saved relation declarations

A saved relation view may carry `resource_identity_wire`, containing the existing
six-field `actql.resource_identity/0.1` SourceView contract. Restoration validates
its shape through the SAME generated SourceView rule in `check_environment`.
Only provider-ID field and output ResourceKind association belongs to the local
relation schema owner. Source parsing, generated-rule work, canonical body and
retained output consume the declaration's remaining byte/node/depth/work bounds. The ordinary
public relation constructor and declarations without this optional wire retain
their existing contracts and bytes.

The static contract is sealed into the same SourceView and Catalog identities.
It contains no current authority, concrete connection revision or boundary CID,
and issues no ResourceReference. The existing Host and value-admission owner
must separately resolve original connection evidence and issue an original
reference; a file name, returned JSON envelope or equal CID cannot stand in for
that authority. Source reads, Content custody, Plan funding and terminal cleanup
remain with their existing owners.

### Public relation catalogue input

`project_relation_declaration_input` mechanically projects an original public
catalogue entry into the existing `restore_relation_row_declaration` input.
It canonically encodes `schema`, `request_schema`, `facts`, `acquisition` and
`resource_identity`, and derives the schema CID through the same canonical JSON
and SHA256 owners. It does not parse a second schema or install an environment.
Unknown view fields remain in the restore input for its strict refusal; public
`schema_cid` and `*_wire` fields cannot inject private restore destinations.

The caller retains the original entry and funds the existing construction
overlap before calling. The supplied positive byte/node/depth ceilings bound
encoding, not capacity, Source permission or a physical read. Native delegates
to this same function with its unchanged 4,000,000-byte, 400,000-node and
64-depth ceilings and existing construction quote. Declaration restoration,
original connection/current checks, Request funding, RowRun capture and physical
cleanup remain separate existing duties. The projection issues only wire DATA;
equal wire does not replace a retained original declaration or acquisition.

## Original JSON page envelopes

`project_row_source_json_page` validates one complete original UTF-8 document
with the existing preserving JSON parser, then selects an array of row objects
through exact object-key paths. It returns opaque envelope DATA containing the
original array byte span as a String, its actual count and an optional cursor.
It never emits parsed numbers, normalizes keys, selects columns, admits a row or
issues Source evidence. The existing RowRun remains responsible for complete
schema/value admission and the original response's charge.

Every present JSON value, including unselected envelope fields, is parsed under
the supplied byte/node/depth bounds before output. Duplicate keys, invalid UTF-8,
missing/non-array items, non-object rows and excess rows refuse the whole page.
Paths use the same exact decoded keys and bounded scalar-text admission. Numeric
lexemes, whitespace, Unicode and CRLF inside the selected array remain exact.
A canonical Signed64 String remains text; a numeric token is never rounded into
an Int64 by this projection. Its eventual typed admission remains unchanged.

A declared cursor path that is missing or null has no next cursor. A present
non-object ancestor or non-text leaf refuses. An empty text cursor is present,
not EOF, and has its actual UTF-8 extent checked. The Common bridge exposes a
real Bool for presence and a Result[String] getter; callers do not inspect an
Option layout. A disabled cursor accepts only an empty cursor path.

The same portable package owns cursor progression, cycle detection and EOF in
`RowSourceCursorProgress`. The reader joins its actual page index and consumed
row count before request/parse and again at advancement. The original typed
envelope supplies the cursor; a separately parsed pure row transform supplies
only its actual row count. A transform cannot substitute continuation or erase
an empty cursor. Page, row and UTF-8 cursor bounds are checked before advancing;
failed checks consume no progress. EOF may exactly fill the final page/row
ceiling, but a further cursor cannot request work beyond either ceiling.

`row_source_cursor_request_rows` joins the same original progress and selects
the outgoing declared page-size hint. An absent hint returns the original
remaining-row ceiling; a positive hint is capped by that ceiling. It neither
advances progress nor narrows the independent response/parse bound. A provider
page still obeys the original row contract even when its request hint was
smaller. The Node adapter forwards that typed result rather than repricing or
reimplementing this decision. The captured additional method/field and its
constructor vectors belong to the same Source reservation; the two extra call
arguments and typed Option/Result overlap belong to the same request quantity.

The portable typed caller can execute on JS and Wasm without giving either
backend HTTP, credential or physical-stop authority. This does not create a
Wasm HTTP Host profile. Fixed query/header capture and transport encoding remain
separate from this request-size decision and are not full portable-family proof.

This is bounded semantic DATA, not another reader or Resource owner. It retains
at most `max_pages - 1` cursor strings, each under `max_cursor_bytes`, and no
parsed page, response buffer, Account, authorization or resource handle. The
same managed reader must back those retained strings and map entries under its
existing Request/Plan; numeric limits are not funding. Node only forwards the
same opaque progress and page objects and maps the typed refusal vocabulary.
Portable Core execution is separate from ordinary installed Host acceptance.

The installed REST factory selects the generic `cursorProgress` construction
mode on its same Source service. The service cache binds that mode along with
the original Source/installation, limits and column count; an old JSON quote
cannot be reused for Core progress. Missing Core capacity refuses before page-reader
or cursor-progress construction. Program DATA cannot select this installation mode.
The thin bridge selects `installed_json_cursor_source_reader_capacity` in the
existing `client_local_host/installed_source_reader_capacity.mbt` domain recipe.
That recipe uses the shared Map construction extent, including bucket growth
overlap, and holds its conservative complete peak until this reader retires.
The original cursor String backing is counted once for at most `max_pages - 1`
strings. Old cursor-Set entries are replaced; identity tracking, response/use
history, credential and physical frames are preserved. The fixed former
cursor-Set header becomes the progress record, whose fields and cursor Option
are declared separately. Synchronous Core results have their own workspace.

The same opaque provider capacity flows through `providerCaptureCapacity` and
the original RowRun reservation before `reader.prepare` can construct progress.
Its response, callback and failed-child duties continue through capture and
the original reader's cleanup. No earlier settling or new reservation follows
from EOF or a current check. The unchanged legacy JSON mode retains its old
recipe. These logical representation tariffs are not backend heap/RSS bounds;
the matching ordinary installed route remains a separate qualification.

Projection is synchronous and has no callbacks, I/O, authority, Ledger, grant,
retry or retirement operation. The shared Reader retains and charges the actual
response before decoding. The parser's original construction inventory and the
selected JSON reader's existing projection/row-wire workspace cover distinct
representations: original bytes, parsed document, exact selected String and later
row admission. The selected String is bounded by the original response extent;
no extra limit, VM price or permission follows from those DATA quantities. The
actual initial/Request/Plan must still admit constructor, retained prefix,
output and failed-child overlap before use. Same-Common page accessors add no
physical cleanup acknowledgement or normal execution claim.

`project_row_source_typed_json_page` uses that same envelope parser and bounds
but retains the selected parsed subtree without creating the selected String.
Its opaque page carries a same-compiled-namespace identity and the original
array byte extent. No parsed tree or response buffer escapes through a public
row accessor. `row_source_json_page_original` exposes the same opaque original
from a legacy wire projection, so an unchanged author transform can retain it.
Changed transform wire is a new bounded parser input; external row wire keeps
the existing parser entrance.

`accept_charged_row_run_projected_page` consumes the original RowRun response
ticket once, verifies the page's namespace, and applies the existing bounded
tree admission and complete schema/value/cardinality/retention checks. It does
not serialize or parse the already selected array again. Foreign pages, closed
reads, wrong schema, missing or extra fields and exceeded bounds still refuse;
there is no wire fallback. The namespace identity is DATA provenance only and
supplies no grant, Resource, separate reservation or physical retirement fact.

Verification is defined by `json_page_projection_wbtest.mbt`, including original
span preservation, cursor state and whole-document refusal, and by the existing
physical row and Signed64 admission cases it calls. Node and RelA use the same
thin `client_row_json_page_bridge.mbt` body. Provider pagination and transformed
page handling remain with the existing REST page callback and shared Reader.
`typed_json_page_wbtest.mbt` separately covers typed row admission, exact Signed64
Strings, NULL/Unicode, schema/bound/cancellation refusal and foreign namespace
refusal. These components do not establish ordinary installed Source acceptance.

### Captured Query Compute binding

`check_row_capture_compute_binding` observes task zero of the same single-capture
DAG. The original RowRun must still own its live holding on that DAG's Ledger,
with no pending cleanup or transferred custody. Source verifier callbacks run
before the final custody check, so synchronous close cannot leave a valid
binding. This allocation-free observer grants no Source/Account permission,
capacity or retirement acknowledgement. The standalone prefix census remains
unchanged. The consuming [ordinary task adapter](../client_local_host/captured-tasks-interface.md)
closes dependent Compute before its caller retires the Source.


### Selected-schema capture measurement

Query capture measures both the complete original input scan and the completed
SELECT output. Its column bound is derived from those same checked schemas
retained by the original acquisition, rather than the unrelated Values default
or a Host maximum. The original ordering work, node, wire-byte and depth limits
remain separate and enforced. This does not grant Source access or change a
provider's declared field bound; strict missing selected properties still refuse.

The existing RowRun reserves the corresponding temporary names/order metadata
before I/O through `row_acquisition_execution_capacity`. It uses the shared
preparation representation policy: n tuple records, n borrowed name references,
up to 3n simultaneous column-growth references, n tuple name/index pairs, and
bounded cursor/control records. Qualified spelling uses the original schema
constructor's own header/UTF16 inventory; unqualified strings stay borrowed.
The two measurements run sequentially, so their variable workspaces use the
larger original extent. Later capture identity measurement overlaps retained
evidence-record names, so the same execution reservation also backs that extent. The existing wire/hash payload envelope is unchanged.
The checked quote is retained in the same immutable RowHost configuration and
added to its same original reservation, with no new Ledger, attempt or cleanup
owner. Physical/current refusal retains the existing reader and Source duties.

For the independently authored 102-column fixture this metadata is 6912 logical
bytes; it is not a heap/RSS measurement. `measurement_capacity_wbtest.mbt` checks
unqualified/qualified arithmetic and the unchanged explicit ordering refusals;
the installed HubSpot wide fixture separately tests complete provider input,
the complete acquisition SELECT port, finite transfer accounting and real cleanup.
The authored Program SELECT is a later Compute result and has its separate
three-field oracle; exporting acquisition Source does not execute that result.

The evidence record writer receives that same original input field count.
Its retained name Array is backed on the same RowRun as well: two Array/backing
headers, up to 2n retained references and the original qualified-name storage.
For 102 unqualified fields this adds 1664 logical retained bytes. Its 3n growth
peak is smaller than the already funded measurement workspace. Parameter,
byte, node, ordering and work bounds remain independent; this replaces neither
the writer's field check nor the receiving schema's nominal validation.

Installed Query and Whole identity callers pass the same live RowSourceCapture
and its exact cached Source. The receiver checks physical identity and the
original observation variant before reading its checked capture schema width;
foreign or closed captures refuse. Legacy generic identity limits stay unchanged.
Query export and restoration independently bind the original checked requirement
before using that capture port's schema width; descriptor counts cannot enlarge it. For 102 unqualified
fields, the late metadata/name overlap is 8576 logical execution bytes, alongside
the separately charged 1664 retained bytes; no new Ledger or authority is issued.

When the Host also retains original input for later dependent reads, its Query
exporter checks the same nominal receiver/input binding against the original
QueryRequirement. Export and reconstruction use that checked INPUT schema's
width, independently of the capture SELECT schema and saved descriptor counts.
The generic original-input export defaults stay unchanged. The original-input
receiving quote retains its existing finite wire/tree envelope and adds the
shared checked-input metadata inventory before allocation on the receiving
Ledger. This issues no new Source observation or receiving permission; current
custody and sliced physical backing cleanup remain required.

Restored Whole Source identity likewise consumes its exact original
ClientInstalledWholeSourceCapacity, checks that Source's nominal acquisition and
liveness, then forwards the actual checked input width. Constructor max_columns
and saved counts are not width evidence; a foreign equal-schema capacity refuses.
The legacy unbound identity APIs keep their original defaults.

## Original finite GET request DATA

`RowSourceGetRead` retains the original preserving parser, its own input copy,
checked path/query/version header and declared page-size/cursor meaning in the
same namespace. It is pure DATA without a Source permission, Ledger, current
observation or physical resource. The author entry returns only the original
wire. The installed Source quotes and reserves the complete parse/target
construction before admission and keeps this original through Source retirement.

`row_source_get_read_page` derives one request from that original, remaining
rows, current hint and an optional exact cursor. Its detached tuple vectors may
be mutated by a consumer without changing the original read or a checked page.
Empty/decomposed-Unicode cursors, literal order and version bytes are preserved.
A copied/foreign read, duplicate/colliding parameter, transport header, unsafe
path or invalid limit refuses before request construction. Provider response
semantics and full row admission remain with their existing owners.

The construction inventories compose shared preserving-parser, decoder/issue,
collection-growth and representation units. They fund original input+copy and
invalid-prefix overlap; quantities issue no reservation or authority. The same
Reader combines one active request/frame peak with its still-live Host transport
quantity, rather than summing unrelated per-source page attempts or dropping
Host encoding. Native Options/tuples/Arrays use the actual canonical bridge;
opaque quantities do not acquire record fields merely from numeric positions.

### Original catalogue wire construction

`project_relation_declaration_wire_input` adapts the same retained public entry
wire through the existing Json parser to `project_relation_declaration_input`.
The Node bridge obtains that wire from the same original `ClientProjectCatalog`
and exact entry index; a JavaScript object is never cast to MoonBit Json.
`relation_public_projection_construction_inventory` is a domain recipe for this
fixed constructor, not another parser, tariff, Owner, capacity grant or policy.
The caller must reserve it on its existing initialization parent before entry.

The borrowed wire scan reports actual UTF8 bytes, UTF16 units U, conservative
outside-string structural nodes N and open-container depth D. Punctuation and
escapes inside quoted Text contribute only to its separate text/writer extent,
not AST nodes. Disjoint public body emissions are bounded by 6U+25N (JSON escapes
and finite Double spelling).
The returned wrapper includes those bodies escaped once more, original opaque
keys/values, exact generated destination/CID spelling and original view slots.
Its encoder ceilings derive from this observed geometry, including D+3, rather
than importing a Native writer policy. Existing catalogue admission and later
Relation restoration retain their own unchanged semantic limits.

The recipe composes existing raw-Json, canonical forest, text-writer, checked
collection/Map growth and representation arithmetic. It separately includes
all per-body traversal/writer controls, projected Json wrappers, fixed SHA256
state/word/block/digit/output arrays, UTF8 backing, digest, hex/CID Strings,
final canonical tree/writer/output and one actual Host `{wire}` carrier.
Data-key text is borrowed without NFC conversion. Conservative failure-prefix
peaks are co-held; no previous reservation is refunded or treated as spare.
This is logical representation funding, not a backend heap/RSS measurement.

The Node loader still needs saved-view Strings for its existing restore quote's
seven parallel arrays and for separately owned File-profile derivation. It funds
that actual JS parse/freeze and the array holders separately. The exact returned
wire is passed directly to the initial restore; it is not serialized again.
The old JS schema/CID/canonical-body constructors are removed from this path's
Host recipe, while alias/data/write/File checks and their holdings remain.
Later native restores, Request/RowRun charge, Source evidence, currentness and
physical cleanup keep their original owners and require their own backing.
