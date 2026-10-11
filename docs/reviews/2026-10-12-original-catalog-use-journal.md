# Original Catalog credential-use journal seam

## Responsibility

The existing credential Resource Owner records a nominal `RemoteCredentialUse` before Provider I/O. Resident recovery currently queries only the credential database; a missing/replaced database plus a missing Checkpoint is not evidence that the original read was never attempted.

The additive Site journal seam retains one exact Catalog use for the original consumer dispatch. `retain_effect_catalog_use` is intended for the Resource Owner's pre-send callback, after its original use record exists and before its final current/lifetime/revocation fence. `effect_catalog_use` reads that retained responsibility independently of the credential database. Neither method authorizes a read or proves that a Provider request was sent, completed, or cleaned up.

## Existing boundaries

- Nominal grant/use admission remains in `remote_credential`. No wire, CID, signed grant, or permission is regenerated.
- The grant and use must match the exact consumer dispatch, task attempt, Site generation, runtime and Catalog operation. The original Host principal, invocation, configured Catalog connection and current permission are still selected/verified by the caller's existing Original/Account/credential Owners. The journal is not a substitute for signature verification or that admission.
- Initial retention requires the existing dispatch in `NativeSettled`/`CleanupActive`, no cancellation, and the current Site binding in the same existing journal transaction.
- Same-use replay is immutable; another grant/use cannot overwrite this original slot. A saved witness remains inspectable independently of current send authority.
- The body is bounded by the journal's existing record-byte limit. This bound alone does not establish aggregate disk or control-object funding. No new reservation/limit or funding claim is introduced in this isolated seam; the calling integration must establish original custody accounting before production enablement.
- Failed/uncertain commit or readback returns an error. Missing/legacy custody stays `Physical(NotFound)`; it is not a first-read permit. No bootstrap/backfill, delete, reissue, cleanup completion, or retry permission is added.

## Remaining production connection

This unit does not yet call the new methods from the credential Resource service. D's public resource unit #1496 (`1c664703363592afb1a57b79feb13370b97af96f`) is being kept separate. Its agreed additive hook position is after original use persistence/raw reservation and before final clock/current/revocation checks; the hook receives the actual nominal use and must finish journal retention before any GET.

The caller still needs an original initial-use eligibility proof and must remove the unsafe missing-use plus missing-Checkpoint fallback. A reconstructed holder cannot obtain that proof from process-local `read_started`, a newly opened DB, or candidate wire. Missing original custody/DB continuity must retain the unresolved responsibility and permit no new Provider read. The legitimate initial admission and legacy-unavailable cases must remain distinct. Record funding, actual authenticated Host/current read/publication permission supply, physical SQLite/Provider tests, and public Cloud approval/Effect/Result/release are uncompleted.

## Validation scope

Two portable binding cases execute the affected projection checks using common-issued nominal requests/grants/uses. They cover exact matching, foreign dispatch, attempt, generation, and another grant with the same use ID. These are not Provider or public Run tests.

Two Native SQLite fixtures cover immutable use retention, reopen, foreign/replacement rejection, missing custody, wrong dispatch state, and writer-lock failure/retry. They require real SQLite and fail if their environment is absent. They have been compiled only; no Native execution or SQLite persistence result is claimed. The affected Native journal/caller is compiled, and the interface is generated with the existing `moon info` generator for JS/Native/Wasm. Hosted CI and Heavy remain disabled.
