# Kintone original record mutation material

The existing vendor Catalog projects mutation material from its original record
observations. `OriginalRecordTarget` retains the complete `OriginalRecordPage`,
its original Form catalog, and the selected original record. Its constructor
takes that page and an existing index, not an ID/revision packet or a decoded
equal object. Native Record Number remains separate from the API ID. Neither
the target nor any equality check is an Effect, permission or current grant.

`match_original_record_target_revision` checks only the presence and exact
revision of that API ID under the same original catalog. Full Preview values,
App/Site/credential generation, current authority, capacity and original
Task/Run/attempt correspondence still belong to their existing Owners. A
successful revision comparison cannot replace any of those checks.

## Deletion request and response

`RecordDeleteRequest` retains a copied ordered array of the original targets
and one bounded encoded document. Its IDs and revisions are paired in the same
order, with the original string spelling preserved. All targets must belong to
one original Form catalog. Numeric ID comparison is used only to reject
duplicate aliases, never to normalize a request ID or ResourceRef. Required
revision checks are not omitted or replaced with `-1`.

The [provider deletion endpoint](https://kintone.dev/en/docs/kintone/rest-api/records/delete-records/)
accepts at most 100 IDs and pairs each with its expected revision. A mismatch
rejects the batch. This preparation rejects excess input instead of truncating
or starting a second request. It does not split work, create a nominal use,
claim a send, issue a grant or commit an Effect.

A complete HTTP 200 empty-object response can produce a private
`RecordDeleteAcknowledgement` retaining that exact request and the original
response digest. The physical Site must first bind the actual response to its
original request/claim. This pure projection cannot establish that binding.
Malformed, partial, non-success or error responses are refused. The observation
is not a physical cleanup acknowledgement. A timeout or missing response has
no successful constructor here. A later absent record is not a retained delete
marker: the existing Effect Owner must preserve Unknown without resend.

## Retention and remaining connections

The original page's decode tree, records and Form catalog stay reachable through
each target until the existing capture/Effect cleanup retires them. A batch also
holds its copied target references and encoded document. Identity and bounded
pair-comparison work overlap that storage. Explicit positive caller limits
bound preparation; they are not reservations, a budget SSOT or an adopted
normal numerical profile.

The physical Credential Site, original current/approval/Preview checks,
same-attempt journal/Unknown handling, and release of every retained original
remain mandatory consuming connections. Insert/update/upsert field material,
attachment custody, process-action metadata and their physical dispatch are
independent unfinished parts of the same Connector outcome. This protocol
material does not advertise installed write support or relax those obligations.

## Original unique Text-key lookup

`RecordLookupRequest` retains the original Form, its positively enforced
top-level unique Text key, exact nonempty text value, selected fields and one
bounded encoded request. It requests `$id`, `$revision`, the key and every
selected field, with an equality query, `limit 2` and explicit `totalCount`.
The provider's [query escaping](https://kintone.dev/en/docs/kintone/overview/query-string/)
and JSON escaping are distinct layers; original Unicode and field codes are
preserved. Query syntax cannot be supplied in place of a field-code token.
See the provider's [saved field-code rules](https://us.kintone.help/k/en/app/form/autocalc/ref_data/fieldcode).

`RecordLookupObservation` retains that same original request and the complete
original page. Only HTTP 200 with an explicit total count of zero and no records,
or one and exactly one complete record matching the original key, produces this
DATA. A short page, missing/null count, 404, partial/error response, duplicate or
different key cannot stand in for this observation. Exact API ID and revision
strings remain separate from Record Number. A fresh observation must refer to
the same physical request; changed presence, ID or revision refuses matching.
The [Get Records contract](https://kintone.dev/en/docs/kintone/rest-api/records/get-records/)
defines the count as matching query records, not a grant or global visibility.

An empty visible result is not proof that no hidden or concurrently created
record exists. The eventual conditional insertion must retain the positively
enforced original key so a uniqueness conflict remains refusal/Unknown under
the existing Effect Owner, never an automatic update, retry or new lookup.
The physical Site must bind the response to the actual original authorized
request and keep current checks around awaits. No public empty-object/scalar
constructor, physical I/O or generic UPSERT create-side admission is added by
this projection. Numeric keys remain unavailable here while the independent
historical Number-domain obligation is unfinished; no Text/Double substitute or
new numeric profile is used.

### Key lookup interface responsibilities

- Responsibility: the existing vendor Catalog projects request/response DATA;
  existing Credential Site, Row capture and Effect Owners retain execution.
- Inputs and outputs: one original Form, unique Text key/value, field selection
  and positive limits produce an original lookup request; its complete response
  produces a matched original page or a typed refusal without partial output.
- Identity: request, Form and observed page remain physically associated;
  equal request bytes or a new equal Form do not reconstruct the original.
- Ownership: the original Form, field selection, query/document, retained page,
  decode cursors and raw-response responsibility remain with the caller's same
  capture child. No independent cleanup Owner is created.
- Synchronization: synchronous matching is not current authorization. The same
  acquisition/Site generation, read decision, Credential binding and original
  Task/Run/attempt fences must surround actual calls and final disclosure.
- Failure: absent/false uniqueness, empty key, unknown fields, malformed or
  incomplete replies, foreign requests, changed targets and exhausted limits
  return no usable observation; they do not select replacement credentials.
- Cancellation: DATA completion neither stops transport nor acknowledges
  physical retirement. Response loss keeps original Unknown without resend.
- Resources: positive key/comparison/column/writer and original page limits
  bound this projection. Original catalog/page/decode trees overlap selected
  arrays, escaped query, encoded document, UTF-8 and response/hash workspace.
  No whole-phase quote, reservation or normal numerical funding is issued.
- Extension: this private Text-key projection introduces no public wire, grant,
  Site, ledger or supported installed mutation claim. Number, physical lookup,
  conditional write and cleanup supplier connections remain separate duties.
- Verification: `record_lookup_wbtest.mbt` checks independent request bytes,
  original nominal correspondence, Unicode/escape preservation, count/key/
  selected-field failures, presence/revision drift and finite refusal. These
  pure Catalog cases are not authenticated HTTP or installed acceptance.

## Original physical deletion port

`sendRawKintoneDelete` borrows the caller's already-owned private kintone token
binding and original request. It performs separately authorized Form and target
observations before the single DELETE. Form revision/field definitions and every
original API ID/revision are rechecked under the original Catalog. The bounded
target query contains only original numeric IDs; it does not accept caller SQL.
The [provider's documented method override](https://kintone.dev/en/docs/kintone/rest-api/overview/kintone-rest-api-overview/#x-http-method-override)
uses POST with `X-HTTP-Method-Override: DELETE` for the exact original JSON body;
the shared HTTP transport's bodyless DELETE rule stays unchanged.
Every physical call uses the original Credential Site journal, full generated
invocation binding, and current callback before send after the resolver await.
The current callback must retain the original acquisition/Site/current authority,
including retirement and cancellation. The port cannot issue that authority.

The trusted caller must have claimed the original Effect before invoking this
port. It retains the same binding, observations and cleanup responsibilities
through refusal and Unknown. The port neither creates that Effect claim nor
reconciles it. A complete response is charged synchronously on the caller's
original RowRun before any later awaited check or decode. Failed decode may
leave that original charge pending until the same Root cleanup. Final current
refusal retains the response; credential-journal success is only nominal
transport evidence. Missing reply leaves the original nominal use Unknown and
starts no retry, replacement token lookup or second DELETE.

### Physical interface responsibilities

- Responsibility: the existing Catalog checks vendor DATA; Account and
  Credential Site retain authority/nominal use; the existing Effect Owner
  retains Preview, original durable claim, application and reconciliation.
- Inputs and outputs: the private typed bridge consumes original opaque
  Catalog/target/request values. The physical port returns exact raw responses,
  with separate response projection; no public applied-row constructor exists.
- Identity: the original App, exact paired IDs/revisions, one token binding and
  generated complete invocation scope stay fixed. Equal foreign wire is not
  original material. Native Record Number is not a locator.
- Ownership: the caller holds the original binding, async frame and Root.
  Physical socket closure and frame retirement must precede Root release;
  partial observations and failed charges remain with that same caller.
- Synchronization: current checks surround awaited resolution/authorization and
  follow every retained response. Current loss never selects another token or
  turns the response into permission.
- Failure: non-success/partial replies remain unclassified original bytes.
  Response loss keeps nominal Unknown, independent of physical cleanup ACK;
  neither missing bytes nor a later absent record proves application.
- Cancellation: the original signal and binding retirement stop subsequent
  sends; pending socket or current callback retains the Root reservation.
- Resources: caller limits bound query/envelope encoding, response bytes,
  fields/rows/cells and comparison work. Original page/Form/targets, field-name
  aliases, query, encoded request, per-call grant/use, all raw responses and
  observation tickets overlap the same retained binding/Root. These units are
  not an adopted normal numerical profile or whole-phase funding.
- Extension: the typed Node/RelA bridge is generated from one source. A missing
  required export refuses before credential entry. This raw port is not yet
  advertised as an installed kintone Effect capability.
- Verification: `kintone-record-delete.test.mjs` drives real Common Account,
  signed Credential Site, SQLite and loopback TLS with independent request
  assertions, refusal/rotation/response-loss/current/retirement counters.

## Original deletion Mapping

`prepare_row_delete_mapping` projects the existing Mapping DATA from one
original RowDeclaration and its exact selected View/carrier-schema members.
It retains the original connector manifest, resource kind and complete checked
schema. DELETE introduces no writable fields or proposed value. The selected
primary field must be present, non-null and key-comparable; this metadata
predicate does not prove a provider uniqueness constraint or issue authority.
The existing Mapping reader and permission Owner still admit the result.

The kintone `RecordDeleteMapping` holds that Mapping beside the same original
Form/declaration. It fixes the API `$id` identity and existing deletion operation,
never Record Number. Matching a request requires the same original Catalog and
complete original declared page selection. Re-admitting equal Form bytes or a
separate equal declaration cannot reconstruct this nominal relationship.

The original carrier fields are preserved exactly, including native empty-text
nullability and required Array fields. A conditional-presence Relation that
cannot project to the existing closed object Mapping refuses this projection;
that is not a language-wide restriction on Relation fields. No schema, View or
Catalog is regenerated to make a request match.

### Deletion Mapping interface responsibilities

- Responsibility: existing RowDeclaration/Mapping and vendor Catalog Owners
  project metadata; the existing Site/Effect retains physical execution.
- Inputs and outputs: original declaration, selected resource/primary field,
  existing permission/approval choice and positive caller limits produce the
  existing Mapping shape, or a typed refusal without partial output.
- Identity: original View output reference, carrier-schema CID and manifest
  correspondence are rechecked; kintone matches original Catalog identity,
  complete field selection and paired API IDs/revisions.
- Ownership: `RecordDeleteMapping` retains its original declaration/Form and
  Mapping. No new Site, journal, cleanup owner or synthetic target is created.
- Synchronization: this synchronous projection and nominal matching confer no
  current grant. Actual acquisition, approval, Preview, dispatch and awaited
  transport/current fences remain mandatory at their original Owners.
- Failure: foreign/mutated original members, absent/nullable primary fields,
  incompatible conditional presence and exhausted limits return no Mapping;
  request mismatch never authorizes fallback, lookup or physical send.
- Cancellation: metadata completion is not transport stop or cleanup ACK;
  existing capture/Slot/Root custody must retain every unsettled dependency.
- Resources: original declaration strings, selected View, retained Form/page,
  Source/Decode/JSON trees and checked schema overlap canonical writer,
  preimage/UTF-8/hash workspace, field arrays and the returned Mapping. The
  same positive caller byte/node/depth/field/View ceilings bound projection,
  not whole-phase simultaneous retention or a funded normal profile.
- Extension: the existing typed Node/RelA bridge forwards the same opaque
  originals; absent exports refuse before physical entry. Equal wire does not
  substitute for an issued original, permission or revision observation.
- Verification: strict Common and vendor whitebox counters cover original
  Mapping admission, exact schema/permission fields, bounded refusal and foreign
  originals. `kintone-delete-mapping.test.mjs` consumes the actual Common bridge
  and compares its schema with that same issued declaration. These checks do
  not claim installed approved vendor deletion, reconciliation or full funding.

## Original checked deletion before-data

`RecordDeletePreview` is private vendor before DATA, not the sealed Common
Effect Preview or an approval. Its constructor requires the same original
Mapping/Form and complete selected record page, checks values through the
existing Catalog/ValueContract admission, and retains the exact original
Mapping, target and checked page. A separately issued equal target or Mapping
cannot replace those originals in its correspondence check.

Before values are emitted by the existing checked-value writer under positive
caller bounds. The original admitted column order is preserved; no canonical
key sort is guessed. Array order and duplicates remain unchanged, and checked
Decimal/date/timestamp wire meaning is not reconstructed through Double or
JavaScript JSON. The generic Effect Owner separately canonicalizes the
resulting object when sealing its Preview.

The version guard is the ordinary SHA-256 fingerprint of the encoded three
original strings `[appId, apiRecordId, revision]`. ID and revision never pass
through a Number conversion, display Record Number or current time. This is
version DATA within the already bound target/installation; a matching digest
cannot establish remote provenance, current authorization or application.
Only the actual authenticated Site may label the original response, and the
existing Effect Owner must recheck the original target/version before claim.

### Deletion before-data interface responsibilities

- Responsibility: the existing vendor Catalog and typed Mapping project
  original checked before DATA; the existing Effect Owner seals and approves
  the actual Preview, while the Site owns physical observations.
- Inputs and outputs: original Mapping/target, positive checked-value limits
  and mutation/output bounds return private before/guard DATA or typed refusal.
- Identity: the complete original Catalog/field selection and physical original
  Mapping/target stay matched; exact App/API ID/revision strings bind the
  version fingerprint without a new identity, wire or CID version authority.
- Ownership: original Form/declaration/page, checked page and original target
  remain retained beside before/guard text; no new cleanup Owner is issued.
- Synchronization: projection is synchronous DATA only. Actual current, read
  decisions, Site generation, response correspondence and approval must still
  be checked by their existing Owners around every awaited physical action.
- Failure: foreign originals, incomplete fields and exhausted identity,
  comparison, value or output bounds return no partial before-data handle.
  A successful projection cannot classify missing or uncertain physical I/O.
- Cancellation: projection completion is not stop, release or cleanup ACK;
  the capture child must retain its original physical dependencies until ACK.
- Resources: original page/Form/declaration, copied record/column/row arrays,
  checked matrix, original target, before writer/output and version hash
  workspace can overlap. The returned view retains the complete checked page.
  These positive bounds are not whole-phase reservations or a normal profile.
- Extension: same-runtime Node/RelA forwards only the original opaque values.
  The generic child currently has no adopted Effect response charge/holding
  supplier; result-retention policy and Source RowRun closures cannot replace
  it. Missing physical funding must remain unavailable before target I/O,
  without a fabricated RowRun, Ledger or unaccounted legacy fallback.
- Verification: vendor whitebox and actual Common Node consumers cover exact
  before values, array order/duplicates, separate equal originals, wide
  revision changes and finite refusal. They do not establish actual provider
  observations, approved physical deletion, reconciliation or installed support.

### Original key lookup physical boundary

- Responsibility: `kintone-key-lookup.mjs` borrows the existing Account,
  Credential Site and private secret binding for two Form observations around
  one original unique Text-key lookup. The Catalog alone interprets its DATA;
  this port neither chooses an Effect nor issues an absence/create grant.
- Inputs and outputs: the original opaque lookup request, original App, complete
  generated invocation scope, independent nominal read authorizations, positive
  limits and original response charge/consume callbacks yield an original
  observation with retained physical responses, or a cause-bearing failure.
- Identity: the same original private binding and request span all three reads.
  Both Form observations must match the complete original metadata and revision.
  Every separately counted operation preserves all generated scope fields;
  lookup ID and revision remain exact API strings, not display Record Number.
- Ownership: existing acquisition custody retains original request/Form, private
  material, transport frame, response bytes and pending response tickets. The
  caller supplies its original response Owner; this port creates no RowRun,
  Ledger, cleanup Owner or independent reservation and performs no release.
- Synchronization: current Account/Site is checked before authorization, after
  awaits and secret resolution, after each response and after final Form before
  disclosure of target DATA. Binding equality does not replace current access,
  expiry or generation. Resolver rotation cannot substitute replacement secret.
- Failure: non-200, malformed, incomplete, duplicate or foreign-key responses
  do not become absence; Form drift refuses the observation. Every received
  body is synchronously charged before an awaited check or decode. Failure
  retains original bytes/cause; lost reply keeps the original claim Unknown.
- Cancellation: abort or failed current does not acknowledge physical stop or
  return a holding. The original binding and caller custody remain pending
  until their real physical frame and original cleanup dependencies retire.
  No automatic retries or replacement lookup are introduced.
- Resources: original Catalog/request and body, Form and lookup response bytes,
  JSON/decode trees and retained page can overlap the private secret, TLS frame,
  journal state, charge tickets and failure observations. Existing positive
  request/response/decode limits bound individual work; a physical caller must
  supply its same-phase funded holding and retain it through confirmed cleanup.
- Extension: the private Node/RelA bridge forwards the same Catalog originals;
  missing matching runtime exports refuse before physical I/O. The generic
  Effect child still needs its original Effect response supplier. Source RowRun
  fixture units are not that supplier, normal funding or installed UPSERT.
- Verification: `kintone-key-lookup.test.mjs` drives actual Common, Account,
  Credential Site, SQLite and loopback TLS for original present/empty responses,
  refusal, scope/current/rotation, lost reply and cleanup. Its independent
  request and locator expectations do not derive from product output. The
  shared response fixture has separate explicit component units; it confers no
  Preview, approved write, live service or normal-profile acceptance.

### Original native write values

The Catalog prepares bounded native field-value DATA from the original Form
and Common checked cells. It preserves exact field codes, text, selection
order and duplicates. User, department and group selections project the same
logical codes into native `code` members; display names are not identifiers.
Date and Timestamp retain their logical types. Native Timestamp writes require
whole-second representability; fractional milliseconds are refused rather
than truncated. Explicit dropdown/date/timestamp null remains a clear request.
An empty dropdown string cannot represent the same logical string after a
native read. Radio-button empty strings select the provider default, and radio
null has no empty write representation, so these inputs are refused before I/O.
The [provider field contract](https://kintone.dev/en/docs/kintone/overview/field-types/)
remains the source for these adaptations and its separate validation still
applies to all supplied options and codes.

This document is held beside the original Form and original checked values.
It supplies no Resource identity, approval, current authority, dispatch claim,
revision or provider result. Omitted fields stay omitted. Read-only/process and
privileged create-only metadata are not ordinary update fields. Number storage
history, Time, original subtable rows and issued Content remain separate
carrier/original obligations; this connection does not replace them with text,
Double, current display settings, guessed row IDs or raw file keys. Required
create fields and original target/revision correspondence must be checked at
the subsequent existing request and Effect boundaries. No installed or live
provider round-trip is inferred from DATA encoding and independent read tests.
