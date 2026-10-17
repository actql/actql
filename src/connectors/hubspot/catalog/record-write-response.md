# HubSpot original write observations

`project_record_write_success` admits an acknowledgement of one original
`RecordBatchRequest`. The official [create endpoint](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/create-objects)
uses HTTP 201; [update](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/update-objects)
and [upsert](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/upsert-objects)
use HTTP 200. The body must be COMPLETE, with exactly one result per original
input and no errors. HTTP success, an accepted nominal Credential use, an
objectWriteTraceId, and a matching value are not Effect Ledger settlement.

Updates correlate by exact record ID. Multiple creates/upserts require an
actual echoed original trace for every result; neither provider array order
nor success/error grouping supplies that correlation. A one-input batch can
admit its sole complete result without an echoed trace, as documented create
responses omit it. Any supplied trace must agree. Upserts also require the
provider's explicit `new` flag. Duplicate IDs, foreign traces/IDs, archived
records, incomplete or malformed responses, mixed status 207 and every other
HTTP status remain unclassified. In particular a generic 400 or 503 is not
proof that no write occurred. HubSpot's [error handling](https://developers.hubspot.com/docs/api-reference/error-handling)
documents partial batch results; this boundary does not convert a partial
response into an all-or-nothing outcome.

The opaque response retains the original request, exact raw-response SHA256
and typed IDs/created flags in original input order. No Common Preview identity,
permission, conditional-write guarantee or cleanup ACK is produced. Explicit
byte/node/depth/row limits bound parsing and overlapping result/maps/raw bytes;
they are not normal numerical funding or a language-level record-count limit.

## Physical Site boundary

`sendRawHubSpotRecordBatch` is intended for the existing installed Row Effect
Owner's send callback after its original durable claim. It performs a real
Account identity read and current schema read before the exact original POST.
Each has its own independently authorized nominal operation. All operations
use the same existing private Credential binding, so rotation cannot substitute
a different account's token after an await. Account/current checks run before
each operation, at the physical send fence and after awaited responses. A read
Allow does not authorize an Effect write. Catalog comparison does not replace
Account, scope, time, generation or credential authorization.

Original observations are retained on later decoding, authorization,
accounting or cleanup failures. They are charged before projection. A lost
POST response remains the existing nominal Unknown; this function has no
retry/relookup/resend, claim or reconciliation Owner. The caller retains the
same binding and original cleanup responsibility through confirmed retirement.
The observation projector can consume the same retained bytes after recovery
without a network call. It does not mark an Effect applied.

This unit is a raw protocol/physical component, not a registered public Effect
installation. The remaining existing Row Effect driver must bind the sealed
Preview, mapping, original claim/request marker, apply-time target comparison,
property-history reconciliation and durable Receipt/result/release. The full
HubSpot read/write/content/operation goal remains unchanged. Component loopback
success is not ordinary installed write acceptance, a live service action,
normal numerical profile adoption or Cloud Effect completion.

## Interface responsibilities

- Responsibility: the Catalog owns typed original response correlation; the
  Site owns physical exchange only. Existing Host capture/Preview/claim/Receipt
  Owners remain separate.
- Inputs and outputs: original opaque request/Catalog, original identity,
  generated provider API, independently authorized operations, explicit bounds,
  original bytes and opaque acknowledgement; no credential material is returned.
- Identity: generated complete Credential invocation binding plus actual portal
  observation and exact original request/trace/record identities; none is a grant.
- Ownership: one original private Credential binding holds the secret/request;
  the caller retains original observations and checked cleanup responsibility.
- Synchronization: current callbacks bracket awaited operations; the Credential
  Owner rechecks after resolver/current awaits and uses retained material at send.
- Failure: typed refusal and raw observations survive; partial/malformed/error
  responses are unclassified, lost POST remains Unknown, no retry is introduced.
- Cancellation: existing signal and binding retirement stop new physical work;
  cancellation/termination is not physical release or an unsent proof.
- Resources: byte/node/depth/row limits apply before parsing/request construction;
  original raw, parsed trees, maps/results and charges can overlap until cleanup.
  No existing RowRun/Effect funding, baseline or numerical profile is inferred.
- Extension: only the existing create/update/upsert batch operations are selected;
  unsupported replies stay unclassified without fallback or a replacement request.
- Verification: record_write_response_wbtest.mbt exercises actual typed projection;
  hubspot-record-write.test.mjs exercises real Common/Credential/Account/SQLite/TLS,
  refusal, rotation, awaited revoke, lost reply and original binding retirement.
  Native execution, normal packed write and live service are separate acceptance.
