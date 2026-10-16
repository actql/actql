# Original record selectors and batch documents

`prepare_record_target` admits a complete selector through the existing Source,
Decode and Common property-value Owners. A top-level record `id` is a nonempty
string. An alternate key requires `require_unique_property` on the original
catalog and uses that property's complete contract. Null, empty or nonscalar
selectors, rounded decimal tokens and unconfirmed unique properties refuse.
Company domain lookup support is not a positive uniqueness fact.

`prepare_record_batch_request` binds create, update-by-id or upsert-by-unique-key
to complete `WriteBody` candidates and original caller-supplied trace strings.
The operation cannot discard a target or substitute another key. Every body
and target must match the entire original catalog. Duplicate canonical
selector values or traces refuse the candidate batch instead of silently
dropping an original item. Provider collation or alias equivalence is not
inferred here: the real target-read Owner must also compare the resolved
record identities before it can send a batch. This
does not impose a new language rule: existing Common planning still owns
duplicate/conflicting logical write normalization.

The body keeps its complete `encode_core.EncodedDocument`, including the exact
byte/node/depth measurements. Batch encoding embeds that immutable document
through `emit_document`; it never reparses caller JSON or rounds a decimal.
The containing output counts each embedded subtree, its own envelope and
separately bounded traces. All original bodies, typed targets, copied member
array, duplicate-check maps, the output writer and final document can overlap.
The original body now retains an Encoder document control in addition to its
string, catalog, copied names and separate canonical Common value string.
These are inputs to the unfinished original wholephase funding inventory,
not a normal numerical-profile admission.

The protocol references are the [create](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/create-objects),
[update](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/update-objects)
and [upsert](https://developers.hubspot.com/docs/api-reference/legacy/crm/objects/objects/batch/upsert-objects)
batch APIs. The adopted caller ceiling is at most 100 members per physical
batch, with independently selected complete-output bounds. A smaller bound
does not authorize truncation or a larger replacement request.

## Remaining physical connection

This is request DATA, not an installed write route or a nominal send claim.
`objectWriteTraceId` is correlation only: it proves neither idempotency nor
application. The original ledger must bind these traces and exact request
bytes before a physical send. Account/portal and credential binding, current
permissions, complete sealed Preview, target re-read and conflict handling,
the configured request-marker property and property-history reconciliation,
response custody, cancellation and cleanup remain separate existing duties.
A missing reply cannot issue a replacement request or become unsent.

Archive, association and workflow operations remain part of the approved full
Connector target and need their own protocol connections. This unit does not
represent an archive as an update or claim that record request preparation
finishes those operations, public acceptance or the complete Cloud Effect path.


The [original request marker](record-request-marker.md) extends this same
Request Owner with explicit persisted physical metadata. It keeps the prior
unmarked API and bytes, and does not turn trace correlation into idempotency
or a matching marker into reconciliation success.
