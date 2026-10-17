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
