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
the original SELECT projection, finite transfer accounting and real cleanup.

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
foreign or closed captures refuse. Legacy generic identity and standalone
restoration limits stay unchanged. Query export independently binds its original
requirement before using that capture port's schema width. For 102 unqualified
fields, the late metadata/name overlap is 8576 logical execution bytes, alongside
the separately charged 1664 retained bytes; no new Ledger or authority is issued.
