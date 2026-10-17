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
