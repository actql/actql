# Native holder original Review artifact route

## Scope and dependency

This private caller change depends on #1464, after #1460, #1462 and #1463.
The final merge destination is main. It adds no public API, wire, identity,
Store role, grant or Owner. The production CLI installation remains a separate
connection; its default publication callback still supplies no configuration.

A configured artifact URL previously had to precede the original checkpoint.
The caller now accepts only independent Host checkpoint parameters and current
policy. It calls the existing Review Owner's `observe`, then
`persist_and_retain_report`. Only that genuinely issued, retained report's
sealed checkpoint supplies the artifact path member. The URL preserves the
configured observation channel's origin, Site and generation, replacing its
`/outbound/observations` suffix with `/effect-reviews/{checkpointCID}`.
HTTP and non-observation destinations are refused without a fallback.

The caller checks live task custody, exact dispatch and current evidence/policy
before observation, after observation, after persistence and before upload.
The existing `upload_review_projection` Owner checks the original Store/journal
projection, confirms its report-bound typed ACK and rechecks current authority
around I/O. Partial persistence, ACK or upload failure keeps the same Review
with its caller for explicit retry. No Source, Compute or Effect is started,
and artifact save is not approval, publication, formal release or cleanup.
No candidate wire supplies the checkpoint CID or a transport destination.

## Verification boundary

`moon check --target native src/cmd/native_remote_resident_site` compiles the
private caller and one selected route-assembly white-box case. That case uses a
Checkpoint issued by the existing sealing Owner and checks preservation of the
configured Site/generation plus refusals of HTTP, a poll URL and a query-bearing
observation URL. It is compile-only: actual Native test execution, Store I/O,
cryptography, HTTP, Provider, public SDK, approval and release are unverified.
Formatting and `git diff --check` are recorded in bounded non-Heavy receipts.
Hosted CI remains stopped. Earlier portable diagnostics for an abandoned public
API proposal are preserved separately and are not evidence for this private
caller change.

The named Catalog read failure that has an original response but no admitted
Catalog remains pending under the existing Owner. Saving that response is a
separate contract decision; it is not cast to successful Catalog Store custody.
