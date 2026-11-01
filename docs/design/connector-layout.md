# Connector ownership and repository layout

The repository layout must make implementation ownership visible. Connector-
specific planning, execution, transport glue, and foreign interfaces belong to
that Connector. Common scheduling, assembly, and cross-Connector verification
remain outside every Connector tree.

## Owned implementation

The DuckDB implementation uses these roots:

```text
src/connectors/duckdb/
  acquisition/        source acquisition
  adapter/            SQL and physical-value compilation
  compute/            fixed-input Compute support
  driver/             common Host lifecycle integration
  host/               acquisition Host bridge
  host_native/        native Host bridge
  host_node/          Node Host bridge
  adapters/native/    DuckDB-specific native FFI
  conformance/        test-only real-engine fixtures

adapters/connectors/duckdb/node/
  ...                 Node I/O and native DuckDB integration
```

The native FFI is Connector-owned because its ABI, loading rules, and physical
behavior are specific to DuckDB. `src/platform_native/` is reserved for
product-neutral operating-system capabilities such as filesystems, HTTP, and
SQLite access.

The conformance package is deliberately inside the Connector tree so its
subject is clear. It is not a product Host, a public SPI, or a dependency that
product packages may import.

### Meaning and physical transport

Connector-specific meaning belongs to that Connector's MoonBit owner, including
request identity, ResourceRef derivation, response interpretation, page
completion and recovery matching. The foreign adapter performs the selected
physical operation and returns its observation. It retains the original opaque
request and cleanup responsibility instead of reconstructing them from fields.
Static Catalog or Command declarations can remain data; this does not move their
identity or recovery algorithms into an independent host-language implementation.

Moving a representation or digest computation does not change its existing
preimage, refusal behavior, authorization or unknown-outcome semantics. Separate
changes to those contracts require their own semantic decision. Shared
approval, dispatch, reconciliation and accounting remain with the existing
common owners. Adding a Source or Command must not introduce a Connector-local
Run scheduler, retry authority or approval state machine.

Standard REST installations hand their complete frozen physical-target DATA
inventory to the existing installed row-source owner. That owner constructs the
selected ordered-field target and its canonical CID during original Source
preparation. Later binding observations retain the same Prepared, immutable
target and installation generation; the exact Core resource/field tuple and
current connection are still compared before and after Account authorization.
Retirement invalidates this selection without acknowledging physical cleanup.
This DATA path grants no permission and retains no Allow or current decision.
Necessary await, response, cancellation and page authorization checks remain.

Custom target callbacks retain full target construction and canonical checks,
including callbacks that return frozen values but depend on mutable state.
External or restored Source bindings still need their original full admission;
copied wire, equal CIDs or a reconstructed Prepared cannot supply the existing
owner's private preparation correspondence.

Bulk physical conversion can preserve Arrow, file or engine representations
without materializing every value as a MoonBit object. Its schema, absence/NULL,
numeric and encoding rules, order, chunks, EOS, custody and simultaneous copy
bounds must still satisfy the selected contract. See the
[bulk execution resource boundary](implementation-port.md#bulk-execution-resource-boundary)
and [language binding boundary](portable-execution-boundary.md#language-bindings-and-artifact-correspondence).

## Composition and integration

Rebuild-time assemblies remain in `src/connectors_builtin*` and
`adapters/connectors-builtin/`. They select installed Connector contributions
but do not own Connector behavior.

Cross-component verification remains in packages such as
`src/query_integration/`, `src/node_host_conformance/`, and the corresponding
adapter tests. Integration code may depend on Connector implementations;
common Host and scheduler packages may not.

## Enforced boundaries

Repository gates enforce three constraints:

1. Common execution packages have no direct or transitive dependency on a
   package below `src/connectors/`.
2. Product packages do not import conformance packages.
3. A Local-only bundle contains no DuckDB package, Node adapter, native FFI,
   addon, or linked DuckDB library marker.

These constraints apply to future Connectors as well. Adding Salesforce,
Neo4j, or another backend must extend the Connector-owned roots instead of
creating new product-specific top-level platform packages.

## Original Effect selection boundary

UPDATE, checked DELETE and `command.target.published_store` use the same existing selection
Owner. Field-target Commands and canonical relation STORE do not acquire this
selection context. Valid mixed occurrences retain their separate original
Stage/Effect/header bindings; equal target strings do not merge purposes.

DELETE intentionally extends this existing selection scope without adding a
kind field or another identity domain. Its eight-field bytes may equal those
of an UPDATE with the same occurrence and original installation. Consequently,
the original checked Header, selector and Mapping determine the required
operation support. Complete original Run admission remains mandatory in
addition to the selection-CID facet; that facet alone cannot prove purpose.
Saved material admission checks the retained Program and environment rather
than resolving current aliases. The concrete DELETE binding inspects that same
publication's complete original Mapping inventory, not UPDATE-only shorthand
candidates. Short UPDATE resolution and all old instance bytes are unchanged.
This static connection issues no physical DELETE capability, before/version
observation, absent-after Preview, conditional-send or cleanup acknowledgement.

`run_publication_host/client_effect_target_selections.mbt` and its package-local
original-data projection retain the checked selection, its original prepared
Owner, canonical bytes/CID and saved-material admission. The eight selection
fields and the existing installation preimage have one MoonBit meaning. The
original prepared/allowed/Run readers still bind the independently retained
Compiled Plan and Run Definition, authorization and optional selection presence.
An equal CID, a copied JS array or parsed saved data cannot construct the opaque
selection or replace those original Owners. Existing absent-context identities
and all canonical preimages are unchanged.

The Node adapter observes the actual installed row factory's configuration,
Mapping inventory and generation, converts those facts, and retains their
physical lifetime. Common compares them with the original selection; JavaScript
does not define another selection schema, digest or canonical equality. Current
checks remain before physical work and after asynchronous boundaries. The
private request-journal installation uses the same runtime's bounded DATA
reader, and owner-only recovery returns the original saved admission evidence;
neither path grants disclosure, write, dispatch or retry authority.

The generated private DATA codec snapshots values once and transports JSON. Its
byte/node/depth ceilings come from that same Owner; it has no semantic field list,
normalization, CID or opaque constructor. Public DATA named `$tag`, `_0` or `_1`
is ordinary data here, not a MoonBit compiler representation. Compiler Result and
tuple interpretation uses the existing generated private binding.

The JS projection borrows the same prepared/selection/runtime references for
the projection's lifetime. DATA conversion temporarily overlaps the input,
bounded detached snapshot/keys and encoded wire; Common admission additionally
uses its bounded source/decoder/canonical writer workspace. These are not free
memory, physical retirement ACKs, capacity reservations or a numerical profile.
Releasing references or completing a synchronous comparison makes none of those
claims. The original Run, Store, Checkpoint, Unknown and cleanup responsibilities
stay with their existing Owners.

## Original Content preparation projection

The existing execution-relation export owns the issued Content Reference and
its per-cell inventory. The existing Effect capture owns the exact prepared
computation, captured input pin, member, Command field and local Artifact.
`client_effect_command_content.mbt` joins those originals in a bounded,
read-only projection; a parsed Content envelope, equal wire or CID cannot
reconstruct that occurrence or replace another Run's original input.

That admission must occur before the transient export's normal finally. For a
checked Command with a mapped Content field, the same Common Owner moves the
exact export reference backing into the existing local Artifact. It copies no
rows, Ref values or canonical material. The old receipt loses its bind/reissue
right; immutable schema, logical identity, bytes and CID facts remain unchanged.
Later preparation reads the moved inventory, never a cancelled export receipt
or a newly parsed envelope. The capture retains the Artifact before the move
can invoke a fallible original-current callback.

The projection reads only a declared Content input mapped from an original
Result field. It checks field/work ceilings and original availability, then
rechecks the same input retention after the Reference's Host callback. Its
private constructor and original back-reference reject copied views. The
installed adapter also checks its original installation/current fence before
and after projection. Invalid, foreign, unavailable or retired inputs refuse;
retention alone is not availability or authorization.

The physical supplier can compare its already-issued CheckedValue with the
borrowed view through `matchesIssued`. Common requires the same original opaque
Reference, then performs that view's existing bounded current check, including
retention after the Host callback. Equal canonical bytes, CID or issuer domain
do not suffice. The method closures share the existing retireable original
capture; each call also holds its CheckedValue argument and observation callback
workspace. Retirement still cuts the original back-reference, not those costs.
This predicate issues no reservation, allocation, byte loan or read permission.

The existing physical Source inventory may retain the exact confirmed Store
holding alongside that issued value and its original candidate, Store authority,
workspace Scope and data policy. Confirmation precedes the synchronous private
receiver and the same availability fence runs again after it. Fresh capture and
saved capture use this same boundary; neither reconstructs issuer custody by
looking up a Reference or CID later. The inventory's typed original matcher and
post-callback entry/current check are also required when selecting this stored
binding. A copied binding or equal-wire issuance cannot substitute for that
entry. The immutable observation exposes no Store, path, key or byte buffer.
The post-matcher fence checks both inventory retirement and the original Source's
current availability; a callback can change the latter without starting cleanup
or replacing the entry. It rechecks inventory retirement after that availability
callback as well. A prior successful match is not a substitute for either fence.
It is metadata custody, not a physical loan, original phase assignment, read
authorization or cleanup acknowledgement. Its extra record and aliases remain
in the Source/Host envelope through their actual lifetimes; temporary Source
cleanup does not retire the committed Content holding or escaped aliases.

The same Owner can additionally borrow a supplier's already allocated
`SharedAllocation`. It first matches the original issued Reference and captured
input, then checks the same live Run Ledger and Resource's exact capacity /
allocation ownership. It reserves and allocates no bytes. In particular,
same-Ledger correspondence does not select an installation or physical phase:
that original assignment and its complete simultaneous envelope must come from
the existing trusted physical supplier, not arbitrary caller tokens.

The borrower is transferred to the existing physical child's custody before
another currentness callback or I/O. Resource admission may itself invoke the
original Host. If a late callback retires the view, the caller must keep the
successfully acquired borrower, refuse new I/O and clean up that same duty;
throwing after acquisition must not discard the loan. View/input retirement,
cancellation, Promise completion and a stored receipt return no capacity.
The exact loan is returned once only after its physical use and last aliases
retire. Returning it neither retires its parent allocation or arena nor affects
another borrower or sibling allocation. Missing physical phase assignment or
funding remains unavailable; this private port is not a read/dispatch grant.

A synchronous trusted Command preparation can borrow the same view repeatedly
for one row/input. The capture retains it before further caller callbacks and
retires it through its existing input cleanup, including failure and cancellation
paths. The view, its original record, row/name cache, callbacks, original input,
Artifact and Reference coexist until those references actually retire. Release
cuts the view's back-references only: it is not byte acquisition, physical FD or
transport cleanup, a capacity loan, a Store ACK, a permission or a numerical
profile. The Artifact then revokes and scrubs that same reference backing with
bounded work. An incomplete scrub retains the same Artifact and parent input
pin for cleanup retry; it does not return the input's allowance early. A future
asynchronous child must remain under that same cleanup Owner
before its first await; this projection does not implement or authorize it.

The private Common/RelA bridges are generated from the existing shared bridge
source and use the normal compiler binding. The focused execution-relation,
input-retention and actual installed Host tests distinguish issuer identity,
work exhaustion, callback retirement, copied views and parent cleanup. Their
scope is not physical Content upload, cold recovery or public Provider acceptance.

## Owned guarded request preparation

Every installed Effect kind may use the existing `prepareRequestChild` port.
CREATE uses the existing unindexed context, with no target-read grant or new
currentness assertion. Command keeps its existing unindexed context and optional
indexed read supplier. A supplied child is never silently replaced by the pure
request fallback.

For guarded UPDATE/upsert/DELETE, the exact conditional request may depend on
an authorized target read.
The Host first obtains each member's original target-read decision, then passes
the row index and a zero-argument read-grant supplier closed over that exact
member, Run/dispatch and row. No write authorization is substituted for the
read, and denied reads create no child or provider work.
The existing selected-preparation current assertion is passed through unchanged
for the child's physical pre-send and post-await checks. An absent assertion
does not manufacture currentness; the driver's actual original Site/Scope and
installation obligations remain required.

The same capture retains the original child before method lookup, currentness
checks or asynchronous preparation. The child acquires the target through its
existing physical owner and derives the final request from that original
before observation. Only then does the existing Common request/selector/value
and Preview path admit it. At capture, `observeTargets` projects the same
original before/version; later apply-current reads and recovery keep their
existing independent obligations. An already identified request is not
patched with a newly read condition.

Children, pending prepare/read/close state, request/before aliases and callback
closures remain in the existing bounded capture inventory. Stage cleanup does
not return parent input/Artifact/Source custody before original child retirement.
Current refusal, cancellation and prepare failure drive that same cleanup;
Promise completion or a cancel request is not a physical ACK. This port issues
no capacity or permission. Missing supplier funding remains unavailable.
The existing Command caller omits `rowIndex` and the selected-preparation
`assertCurrent`; its indexed `authorizationForRow` callback is optional. Typed
consumers distinguish these contexts by the presence of `rowIndex`, preserving
the required zero-argument supplier for guarded rows. A Command never receives
a synthetic row index or read grant to satisfy a declaration.

Pure synchronous preparation and the existing Command child path are unchanged;
this connection does not add DELETE to the separate saved-selection domain.

## Original guarded row deletion

The existing installed Row Effect accepts an explicitly installed `delete`
kind. The checked Mapping and original input select the target; the driver
prepares that exact target with no proposed value. An empty object, null, an
UPDATE payload or a Command input cannot stand in for the absent value. This
extends the existing lifecycle, not its authority or the provider's supported
operations.

The original per-row target-read decision precedes observation. The sealed
full-diff Preview retains the observed before-value and version guard, states
`after: {state: 'absent'}` and `intended_changes: {state: 'not_applicable'}`,
and binds the original request CID. Mapping approval remains independent of
Account Allow. Preparation, commit refresh, claim admission and restored
request comparison retain their existing current and nominal-selection checks;
an observed or acknowledged HTTP response alone cannot authorize deletion.

The original capture, source holdings, request children, Ledger claim and
response custody retain their existing owners and cleanup laws. Cancellation,
a thrown hook, missing ACK or a lost response does not become an unsent or
released outcome. The same request is not resent to turn an unknown result
into success. DELETE request/response codecs and any reconciliation evidence
remain provider-owned; this generic connection does not infer them from a
record ID, equal bytes or an absent proposed value.

The adapter additionally retains a delete capability bit only for an actual
installed delete driver and a Mapping with its own delete permission rule.
Existing non-delete observation shapes are unchanged. These bounded DATA
projections and their temporary field records overlap the original input,
request, Preview, captured payloads and cleanup-pending holdings; they issue
no capacity reservation or numerical profile. New provider kinds still need
normal Owner admission and physical acceptance, rather than a permissive
fallback.

The focused real Common/SQLite capture test independently checks the complete
DELETE Preview and rejects substituted values and targets before send. The
shared test assembly preserves the original Run, Store, journal and awaited
stage disposal, with a Salesforce wrapper selecting its original unit reader.
Capture evidence alone does not establish physical provider deletion, resolved
approval, restored application, pristine installed artifacts or full funding.

## Public Row Effect request kinds

The public connector declaration mirrors the existing installed Row Effect:
DELETE has an absent proposed value (`undefined`); create, update, upsert and
Command retain their original object input. `RowEffectDriver<Request, Current,
Kind>` carries the selected kind through preparation, request facts, entries
and callbacks. Its existing default remains create/update/upsert, preserving
value-bearing callers. An explicitly selected DELETE driver cannot return a
null or object value from either preparation or request facts. Unspecialized
entries cover all actual kinds; consumers requiring an object specialize the
kind instead of asserting away possible absence.

The existing Command variant has its own original Command contract member,
not a fabricated Mapping. Its value and optional indexed read context remain
unchanged. The public declaration adds no Command permission, installation,
capability or execution fallback. As before, a guarded child is returned
synchronously before its first awaited preparation and retains original
release/retry/status custody; the type does not interpret preparation
completion or a missing ACK as retirement.

Actual public TypeScript consumers cover DELETE, the existing value-bearing
path and Command. Independent invalid consumers require rejection of dummy
DELETE values, omitted value-bearing/Command inputs, an asynchronous child
factory and missing cleanup. These are public type checks, not a runtime
build, physical Provider operation, installed artifact or numerical-profile
acceptance; the existing runtime and actual Owner evidence keep their own
source qualifications.

## Original absent UPSERT observation

- Responsibility: the existing installed Row Effect retains the original
  provider-observed presence when authoring its sealed Preview and refreshing
  preflight. The vendor Catalog/Site still obtains and interprets the actual
  original lookup; a JavaScript discriminant or type is no provenance proof.
- Inputs and outputs: `observeTargets` retains the original present
  `{identity, versionCid, before}` form (optional `state: 'present'`). Only an
  UPSERT may return `{identity, state: 'absent'}` without before/version fields.
  It yields the existing private before/guard states, not a new public wire.
- Identity: original request target and observation identity must match; the
  same sealed row CID, original Mapping, prepared input, Preview and Run remain
  bound. Empty objects, null, omitted fields, 404 and unavailable observations
  cannot substitute for an explicit authorized complete lookup observation.
- Ownership: existing capture/request children retain original reads and their
  response/material dependencies. The Site retains current access and physical
  custody; this projection creates no Owner, Ledger, claim or permission.
- Synchronization: insert-side UPSERT emits before absent and a not-applicable
  version guard. Present-side UPSERT, UPDATE and DELETE retain version guards.
  Every apply refresh still reads each original target under its own decision;
  a presence change refuses before dispatch rather than switching the sealed
  request branch. Version observations stay paired by original row Preview CID
  in its sealed canonical order; existing Common checks reject changed versions.
  The existing Common Owner authors canonical target dispatch order separately
  from changes in original source/Plan enumeration. The adapter projects that
  sealed row-CID permutation to the same original requests, observations, keys
  and durable claims; it does not sort display names, partial CIDs or locators.
- Failure: absent observations with before/version fields, unknown presence,
  foreign target identities and absence for UPDATE/DELETE refuse capture.
  Provider conditional creation must enforce the same original unique key and
  reject races; generic Preview support does not authorize blind native upsert.
- Cancellation: observation completion is not physical stop or release. Original
  children, response tickets and Store holdings remain under existing cleanup;
  Unknown outcomes and missing acknowledgements cannot become unsent/success.
- Resources: bounded observation envelope copies, original before references,
  row identity arrays, temporary version-row Sets and current version Map overlap
  captured inputs/response material and canonical Preview workspace. The bounded
  target inventory additionally overlaps raw/canonical target wires, UTF-8
  parsing workspace, source-index pairs and the returned original index array. Their size
  follows the admitted row inventory; no history Map, arbitrary cap or numerical
  funding default is added. The temporary collections retire after preflight.
- Extension: the additive public driver union restricts absence to UPSERT and
  preserves old present/value-bearing/Command callers. Shared physical Effect
  funding remains a separate original supplier; Source fixture units cannot
  replace it or unlock installed vendor lookup/create.
- Verification: `installed-row-upsert-absence.integration.test.mjs` uses actual
  Common/SQLite capture, sealed Preview and target-guard admission with an
  explicitly trusted finite observation driver, not a physical vendor. Public
  type checks independently remove expected-error markers. Original guarded
  UPDATE/DELETE and request-child regression tests remain separate assertions.

## Original member recovery in a composed Set

- Responsibility: the existing installed Row Effect routes recovery to each
  original installation; the vendor driver decodes its retained request
  material. This does not introduce another executor or credential issuer.
- Inputs and outputs: optional `recoverMemberRequests` receives the unchanged
  whole `previewWire`, durable capture, recorded claims and parsed body, plus
  increasing global `memberIndexes`. Its request/current arrays follow that
  selected order. The singular `recoverRequests` protocol is unchanged.
- Identity: each selected position belongs to the nominal installation retained
  for that original Effect occurrence. Rebuilt requests still match the original
  durable request CID, approved value and target. No sliced or reauthored Preview
  substitutes for the whole Set or changes its CID.
- Ownership: original installations retain their Sites, Catalogs, callbacks and
  cleanup duties. The common stage retains the whole Preview, requests, current
  observations, claims and publication custody; composition owns no replacement
  installation or independent close operation.
- Synchronization: reconstruction is synchronous and performs no provider I/O.
  Whole-Set commit authorization and the original installation's current checks
  still precede dispatch. Applied claims remain applied across restart.
- Failure: missing scoped recovery support, foreign installation, duplicate or
  out-of-range selected positions, and request/claim/Preview disagreement refuse
  before sending. Unknown outcomes are retained and are never resent as unsent.
- Cancellation: successful reconstruction neither cancels a Run nor confirms
  producer stop, physical cleanup, publication or release. Existing cancellation
  and cleanup owners retain those decisions.
- Resources: selection is bounded by the original member/row limits; the selected
  index snapshot, per-owner output arrays and full Preview/Catalog decode overlap
  remain part of the existing Host phase's retained inventory. Bounds and decoded
  DATA alone do not establish physical capacity or release backing.
- Extension: this composition profile remains source-free VALUES with CREATE
  members, equal admitted runtime/Ledger location/limits, and explicit scoped
  support when retained-request recovery is required. It does not newly admit
  guarded, Command, imported-source or Model compositions.
- Verification: `installed-composed-recovery.integration.test.mjs` exercises two
  actual installed Sites, a shared admitted account configuration and original
  Set recovery without resending the applied member. Routing refusals, singular
  recovery and bounded index capture have separate focused consumers.

### Calendar configuration reader lifetime

Calendar retains supplied configuration readers before awaiting reads. The
existing identity JSON port and optional installation configuration reader keep
the original receiver and own data methods. Both methods are captured before
the first read; accessor-backed or incomplete readers refuse before I/O.
The configured CA byte limit, PEM validation, ASCII authority bytes and binding
hash remain unchanged. Calls without a reader keep the existing direct bounded
reads. Original read errors and their cleanup duties propagate unchanged; the
connector does not retry or retire an installer-owned reader. Source capacity,
current authorization and physical cleanup remain their original obligations.

### Original configuration readers

Notion and Slack retain supplied configuration readers before awaiting reads.
Their installation identity consumes the existing JSON read port. When the
installer supplies a configuration reader, both own data methods and their
original receiver are captured before the first JSON read; the selected text
reader receives the unchanged profile CA bound. Accessor-backed or incomplete
readers refuse before reading. Omitted readers retain the existing bounded
direct reads.

The original pending read error and cleanup handle propagate unchanged. These
adapters do not retry or retire the installer’s reader. Original PEM validation,
ASCII bytes, workspace bytes and binding hashes remain separate from reader
selection, as do Source admission, current authorization and physical cleanup.

The existing configuration-reader owner selects original methods for connectors.
`captureConfigurationReaders` captures own JSON/text data methods and their
receiver without opening a file, acquiring permission or owning cleanup. It
rejects proxy/accessor/incomplete readers through the connector's original
refusal callback; a returning callback still refuses. Connector adapters retain
their error identity, profile validation, CA bounds and byte/hash semantics.
This shared selection does not replace currentness or resource admission.

When the initializer supplies its existing `readOriginalText` method, selection
captures that own data method and the same receiver before any read awaits.
The initializer funds the opened file's observed extent and retains its physical
cleanup; connectors neither select a replacement byte ceiling nor fall back to
the bounded text reader. An omitted capability remains absent. Malformed or
accessor-backed capabilities refuse without invoking them. Original text and
pending cleanup failures pass through unchanged.

The same selection independently captures the initializer's optional
`readOriginalBytes` method with its original receiver. It returns the original
byte result or Promise without text conversion or copying. Callers require that
capability only for the selected byte input; its absence does not manufacture
a text substitute or require a byte reader when no such input was selected.
The initializer retains physical admission and cleanup responsibility.

## Standard CREATE declaration

Standard JSON write requests use the existing captured connector-recovery
record. It retains the complete plain request DATA, logical value and original
request CID under the existing contract wire/node/depth bounds. Restoration
selects the original member slot and full transport binding, then restores that
DATA without invoking the provider request mapping or creating a new tag.
The existing authenticated capture, approved Preview, claim and currentness
checks still validate it before use. This does not reconstruct opaque native
provider objects or authenticate a bare saved record; those require the
provider's complete existing codec. Missing saved material refuses instead of
repreparing. The existing capture owner remains responsible for the real saved
bytes and their same-Run retention; a metadata limit is not a capacity receipt.

The ordinary Effect loader forwards the original Host installation services
from the embedded owner. Before invoking an installer it retains the exact
selected installation and runtime association in that same service owner.
Profile refusal still precedes runtime selection; a copied service or changed
runtime refuses before installer acquisition. An absent service preserves the
legacy installer envelope. Existing failed-initialization and adapter cleanup
remain with their original owners. This installation/Site connection does not
supply a Run admission, confirmation read, grant or physical operation budget.

Standard GitHub comment and Sheets append installation uses that original
service's `openRowSite` factory. The provider supplies the unchanged connection,
immutable Site configuration, secret resolver and published approval-target
predicate. Host root, principal, runtime, currentness and Account ownership come
from the existing service. Source, publication and Sheets range installation
retain their existing paths; an unavailable service retains the legacy opening
path. Factory refusal propagates without a second Account or Site acquisition.

The existing installed Row Effect accepts either a standard `write` declaration
or an advanced driver. The internal `deriveInstalledRowWrite` adapter derives
routine hooks without another execution owner. Provider mapping runs once on
the same deeply frozen proposal value; a private original-request association
retains that value and the exact admitted HTTP projection. Copies cannot supply
facts, send or classify through that association. Provider-issued CIDs remain
unchanged. Plain HTTP request identity includes the installation namespace,
boundary, operation, fixed origin and exact method, target, ordered headers and
body bytes, without parsing or normalizing the body.

Standard transformation and classification callbacks receive closed provider
DATA views. The transform sees only the original resource and logical value;
classification additionally receives the same request and observation, with
the original presence or absence of headers. Internal Run, Preview, grants,
currentness and child lifetime ports remain with the existing Row Effect.

The adapter captures fixed transport and callback inputs before provider awaits.
It checks the original grant's origin and uses the existing scoped credential
invocation for one send inside the Row Effect's durable claim. It preserves the
original observation/header envelope and original transport errors. It neither
authorizes nor retries nor settles a response. Provider subject/target checks
keep their existing separate resource and read operation; response classification
cannot manufacture a confirmation, Receipt or OperationRef. Advanced conditional
write, recovery and reconciliation semantics remain under the same Row Effect.
