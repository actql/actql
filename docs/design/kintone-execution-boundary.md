# kintone original metadata and execution boundary

The kintone Connector uses the existing installed Row Source, RowRun,
Credential Site and Row Effect responsibilities. Its vendor-specific metadata,
record wrappers, query encoding, revision handling, attachments and process
operations do not introduce another acquisition engine or authority owner.

## Original Form Fields metadata

`connectors/kintone/catalog` projects a complete supplied Form Fields response
under explicit positive caller byte, node, depth, field-count and total
field-code bounds. These are finite physical projection bounds, not language
limits or an adopted numerical profile. An over-limit or malformed response
returns no partial catalog.

The original property key must equal its field code. Labels do not rename a
field. Subtable paths preserve their original parent association. Option-map
keys are external values; they remain exact Unicode text rather than normalized
source identifiers, and option labels cannot replace those keys. Projection
getters return copied path and option arrays. Missing required/unique metadata
remains unconfirmed, distinct from an explicit false value. Unknown native
types can be retained as metadata without claiming a readable or writable
ActQL carrier.

The App ID supplied to this pure projection is a caller label: the Form Fields
response does not echo it. The original settings revision and response digest
are data, not credentials or proof of live deployment. The physical caller
must retain the actual authenticated request and distinguish the live
`/k/v1/app/form/fields.json` endpoint from its preview counterpart through the
same existing Site, nominal use and current authorization. A matching metadata
revision or a successful field comparison does not grant I/O or publication.

The supported custom update-key shape requires original `unique: true` on a
top-level Text or Number field. A configured name, a label, false/missing
metadata or apparently distinct sample records cannot establish that provider
constraint. This static eligibility does not perform a lookup, inspect row
duplicates, approve a write or replace current revision and authority checks.

Number `displayScale` and calculation `format` remain original metadata.
Neither provides an invented Decimal precision or permission to round a
provider value through binary64. Time needs the shared checked logical Time
contract; it is not replaced by String, Timestamp or Decimal.

The complete metadata bytes, parsed source/decode trees, field records,
subtable-path arrays, option references, response-hash workspace and returned
projection can overlap within the original caller's acquisition lifetime.
The parser bounds do not reserve that lifetime or settle its custody. Physical
secret membership, current checks, Account/funding, transport and retained
cleanup remain with their original owners.

## Original record-page observations

`project_record_page` validates a complete bounded Get Records response against
the same original Form catalog and an explicit top-level field selection. The
requesting physical caller must include `$id` and `$revision`. A missing locator,
missing selected field, wrong native wrapper, duplicate record ID or malformed
subtable returns no partial page. Every selected table retains its original
child-field association and row IDs; requesting a table is distinct from
requesting one of its children as a top-level field.

`$id` is the provider's API Record ID (`__ID__`), retained as its original
numeric string. The app-code-bearing `RECORD_NUMBER` remains under its original
field code, even when its value happens to equal `$id` without an App Code.
No prefix removal, missing-ID synthesis, alias or cross-App identity inference
is permitted. Target identity still requires the original API ID and the
existing App/installation owner. A Record Number is not automatically a custom
update key.

The returned immutable decode cursors retain native data, not admitted logical
Values. Text, numeric lexemes, minute Time, codes and file sizes are not rounded
or replaced by another type. Documented empty arrays and nulls remain distinct
from missing values. File keys remain download observations, not Content
references or grants. Principal display names do not replace their codes.
Logical Decimal precision, shared Time/int64, checked contracts, relation
declaration and actual RowRun ingestion remain separate consuming boundaries.
`totalCount` is observed data, never a completion or cleanup acknowledgement.

The page holds its original catalog nominally. Reprojecting equal metadata or
comparing a settings revision does not establish that association, current
authority, same credential acquisition or physical settlement. Parsed response
trees, selected field records, table row arrays, retained IDs/revisions,
duplicate-detection maps and digest workspace can overlap. Their positive
projection bounds are not a reservation or whole-phase funding proof; the
original caller must retain that custody through its existing cleanup.

## Checked record carriers and storage precision

The original live App General Settings response observes configured precision.
Its `numberPrecision.digits` and `decimalPlaces` have a documented range
meaning: the integer part has at most `digits - decimalPlaces` digits and the
fractional configuration is `decimalPlaces`. However, changed settings apply
when each record is next updated: existing records can retain earlier values.
Current settings and a matching Form revision do not prove one fixed-scale
historical column envelope. The normal numeric schema remains unavailable
without an exact original representability contract. This is unfinished
Connector work, not a permanent restriction or a supported numeric profile.
Independent nonnumeric fields do not need a fabricated numeric default.

Field `displayScale` stays display metadata. It neither narrows the stored
read domain nor causes rounding or an excess-scale refusal against the
display setting. For example, `1.007` displayed as `1.00` remains the original
value. The Connector does not repeat the provider's configured rounding mode.
`admit_record_number_value` separately admits one original lexeme under an
explicit existing Common Decimal contract. That per-value result does not
establish a Source column contract or infer history from current settings.
The original strings and metadata remain available after refusal. Any full
numeric-domain resolution belongs to the existing ValueContract owner;
the Connector does not widen Common or select an arbitrary `decimal(38,10)`.

Checked record projection reuses Common ValueContract and Value admission.
Codes stay codes, arrays preserve order and duplicates, and each table object
keeps its original row ID and child contracts. Calendar validity is checked
by the existing Date/Timestamp owner; UTC whole-second response spelling gains
zero milliseconds without changing its instant. The canonical relation
field-map is emitted by the same contracts before physical record I/O. Required
flags constrain future writes and do not narrow historical nullable reads. Field
names that Common cannot represent are refused, never normalized or aliased
into a different original field.

The returned checked matrix is input to the existing RowRun, not a new
acquisition or completion. Its original page remains retained. Copies of
returned arrays cannot alter either original projection. Shared logical Time,
int64 revision and issued ContentRef production still require their respective
owners; missing support is unavailable rather than String, Double or a
fabricated reference.

Original Form, General Settings, record bytes/decode trees, generated contracts,
converted Source nodes, checked values, retained row matrices and schema output
may overlap. Positive limits bound projection and output; they do not reserve
this lifetime, adopt a normal numerical profile or discharge physical cleanup.
The existing Site must still bind the actual authenticated same-App live
requests, generation and current authority. Equal data/revisions are not that
authority or an ACK.

## Installed UPDATE request and driver

UPDATE responsibility: the provider adapter connects the existing same-runtime
native Mapping, proposal, original target, revision-checked request and typed
acknowledgement to the installed row Effect. The shared Host owns Preview,
Checkpoint approval, durable claims, Unknown, settlement and physical cleanup.

UPDATE inputs and outputs: the bounded mapped object and exact API-id String
produce a logical proposal. The complete original Form is rechecked around the
target read. The native checked before object includes `$id` and every declared
before field. The original observed revision enters the native PUT body only
after that target has been projected; no default or guessed revision is used.

UPDATE identity: the immutable binding includes connector, origin, app, resource,
Site and generation, Mapping ref/CID and codec. Final request identity also binds
the original logical request, dispatch tag, complete original target-body digest
and exact serialized PUT body. Equal copied opaque carriers cannot supply it.

UPDATE ownership: the adapter retains native DATA originals and captured runtime
methods. It issues no Account decision, permission, claim or physical ACK. The
driver passes the SAME Site-issued metadata authorization to its physical child;
the invocation useId is separate. Target reads use their original same-row grant.

UPDATE synchronization: each describe and target phase performs fresh authorized
Form reads. Target current, cancellation and credential fences remain in the
existing physical child. An immutable metadata holder is not a reusable current
proof. Captured native, Site and Account methods keep their original receivers.

UPDATE failure: schema, complete before-value, revision, id, Mapping, request-tag,
body and member/claim mismatches refuse. Non-success, incomplete or unrelated
responses remain unclassified, never absence, known nonacceptance or a resend.
Failed physical read observations remain attached to their original cause.

UPDATE cancellation: existing signals are checked before reads and sends. A late
abort must not discard an already observed write response. Socket and response
custody, pending cleanup and Root retirement remain the existing Host duties.

UPDATE resources: parser, value, identity, comparison and writer bounds remain
distinct. Cold before output uses its response bound, independently of the PUT
output bound. Full saved wire and decoded target bytes are bounded before
restoration. Positive limits are not funding: the standard installer must reserve
the simultaneous original material, construction and physical-child backing.

UPDATE extension: cold restoration checks the complete saved binding, original
request tag, native values/target/body, approved row and claim correspondence.
It performs no I/O, new request selection or resend. Node and generated RelA
delegate to the same native validators; no parallel validation implementation is
introduced. This driver alone does not establish a funded standard installation.

UPDATE verification: actual compiled native boundary cases cover wide id/revision
strings, independent before/PUT bounds, copied and substituted material, complete
Form/target drift, metadata versus target grants, response correlation, lost
reply and cancellation custody, original Checkpoint binding and cold tampering.
Explicit component ports do not establish ordinary approval or provider sends.

## Original Common acquisition and checked-contract handoff

The connector's record declaration retains the original Form projection and
the declaration issued by the existing Common Row Source owner. It generates
no separate Catalog identity algorithm. Preparation selects the original
checked QueryRequirement and the same declared view through Common. A matching
body, field name, App ID or CID does not substitute a different acquisition.

An installed reader borrows an already-begun, accounted Direct RowRun once.
Before response handling it binds the same physical-stop observation into the
original cleanup slot. Actual received body bytes are charged before native
decoding, and the resulting typed cells are admitted using the acquisition's
exact original input contracts. Equal independently generated CheckedValues
are refused by Common's nominal input buffer. Contract comparison is bounded;
it is a data check, never authority to read another App or change a column.

The mandatory physical `$id`/`$revision` observations remain in the original
native response even when the checked projection does not expose the locator.
Only the original selected field codes can be handed off, without aliases,
dropped selected fields, JSON roundtrips or numeric conversion. Unsupported
numeric-history and shared-carrier projections remain unavailable before
acquisition preparation, as described above.

The Host remains the sole finish, residual/capture and close owner. Neither
`totalCount`, a successful page, logical abort nor a callback invocation proves
that transport stopped or that a scan is complete. Failed decode, admission or
physical stop retains the same original RowRun/reservation and cleanup debt;
the reader cannot create a replacement attempt. The actual page protocol and
same-App credential/current checks remain with the existing physical Site.

The declaration, original Form/settings, acquisition, borrow, current page,
decode tree, expected contracts, column indexes, checked matrix, residual,
callbacks and return frame may overlap in the original caller's lifetime.
Provider overlap must be supplied to that same owner's existing reservation;
the finite parser limits or byte ticket do not fund these objects. Confirmed
transport retirement detaches the reader's original page, while Common retains
its captured input until the original Host closes it. That ACK is not proof of
GC/RSS reclamation or retirement of all escaped metadata/frames; the caller's
original holding responsibility persists to its actual alias/frame boundary.
No normal numerical profile follows from this typed handoff.

## Provider references

- [Get Form Fields](https://kintone.dev/en/docs/kintone/rest-api/apps/form/get-form-fields/)
  defines original field codes, types, settings revision, nested table fields,
  required/unique flags and option metadata, with separate live and preview
  endpoints.
- [Update Records](https://kintone.dev/en/docs/kintone/rest-api/records/update-records/)
  requires the duplicate-prohibition option for Text or Number update keys;
  record revision checks and additional create permission for upsert remain
  distinct requirements.
- [Field Types](https://kintone.dev/en/docs/kintone/overview/field-types/)
  distinguishes API Record ID from Record Number, specifies the native
  type/value wrappers, table row IDs, attachment metadata and empty responses.
- [Get Records](https://kintone.dev/en/docs/kintone/rest-api/records/get-records/)
  returns complete selected record fields and a nullable string total count;
  table children cannot be requested independently of their table.
- [Get General Settings](https://kintone.dev/en/docs/kintone/rest-api/apps/settings/get-general-settings/)
  supplies original configured precision and App revision, with a distinct preview
  endpoint.
- [Field entry limits](https://us.kintone.help/k/en/app/form/othersettings/field_restriction)
  defines integer and fractional storage ranges; the
  [Number field](https://us.kintone.help/k/en/app/form/form_parts/number)
  documentation distinguishes display truncation from unchanged stored values.
- [Precision and rounding settings](https://us.kintone.help/k/en/app/form/othersettings/significant_figures)
  states that changed settings apply on each record's next update, so current
  configuration is not a historical column envelope.

These metadata projections are not registration or installed acceptance of a
complete Connector. Record acquisition/conversion, content, writes, operations,
approval, restoration, Unknown/nonresend and physical cleanup still require
their real existing-owner execution paths.
