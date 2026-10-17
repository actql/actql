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
