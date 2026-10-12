# Native holder independent Review policy loader

## Scope and connection boundary

This private loader depends on #1466, after #1460, #1462, #1463 and #1464.
The final merge destination is main. It prepares the independent Host inputs
for the existing Catalog/Review caller. It does not register a CLI option,
change `effect_evidence_read` from false, install Provider access, start a Run,
issue a grant, save evidence or claim approval/publication/release.

The Host supplies its root, existing output export limits, configured runtime
and original Store authority independently of Program/poll/report bytes.
The configured consumer `RemoteInputBinding` CID remains an expectation:
`prepare_holder_effect_catalog_review` checks it against the read-only
projection of the original captured consumer before Catalog Provider read.
It is not the initial Source producer binding, a new hash or a permission.

The loader admits the complete original result-retention wire through
`admit_publication_contract`, compares its expected CID and checks its time
intervals. Existing `admit_hashed_effect_dependency_body` admits the retention,
metadata-retention and clock policy bodies. The capture/Review Owners still
validate their exact original references and full evidence closure; loading
these bodies alone does not prove that relationship or authorize acquisition.
No policy or material is reissued from a shape or a candidate CID.

The supplied output export limits remain unchanged. Other settings are bounded
by the existing wire/work and 512 MiB retained-capacity ceilings. No reservation
is made or returned by the loader. Its snapshot continuity callback checks exact
configured contents before/after admission and on later reads. Continuity is
not current evidence disclosure, Reviewer permission or Provider write authority.
Those independent Owner checks remain required at the production entry.

## Operator input files

Each file is read through the existing bounded-file Owner, with a per-file
limit no greater than the Host's `max-file-bytes` and 65,536 bytes. Required
fields may not be empty. Fixed names are:

| Purpose | Files |
| --- | --- |
| Original selection | `review-stage.txt`, `review-effect-id.txt`, `catalog-api-version.txt`, `review-source-binding-cid.txt`, `effect-connector-id.txt` |
| Original retention | `review-retention-cid.txt`, `review-retention.json` |
| Retention dependencies | `review-retention-contract-cid.txt`, `review-retention-contract.json`, `review-metadata-retention-cid.txt`, `review-metadata-retention.json`, `review-clock-cid.txt`, `review-clock.json` |
| Original Checkpoint parameters | `review-checkpoint-id.txt`, `review-created-at.txt`, `review-expires-at.txt` |
| Local custody key | `review-store-key.hex` (exactly 64 lowercase hex digits representing 32 bytes; never logged) |
| Evidence limits | `review-max-bytes.txt`, `review-max-nodes.txt`, `review-max-depth.txt`, `review-max-work.txt`, `review-max-fields.txt`, `review-max-rows.txt`, `review-max-capture-workspace.txt`, `review-max-utf16-units.txt` |
| Dependency limits | `review-dependency-max-entries.txt`, `review-dependency-max-bytes.txt`, `review-dependency-max-depth.txt`, `review-dependency-max-references.txt` |

Catalog grant/issuer/Provider files from #1460 are separately installed only
with genuine original producer context. This loader does not read those files,
assume a future captured invocation or supply a future artifact URL. #1466
selects that URL only from the genuinely saved original report.

This finite adapter supplies a refusal for an accidental target-observation
callback. The mapped-create Owner does not call it; update/PATCH must not receive
a fabricated target, an implicit observe grant or a success fallback.

## Validation and remaining work

The selected matching check is `moon check --target native
src/cmd/native_remote_resident_site`, under the bounded non-Heavy guard. The
added exact-length/lowercase custody-key boundary case is compile-only, not an
executed Native test. The unused loader/fields are expected while the separate
production evidence authorization entry is not connected. Hosted CI is stopped.
No crypto, filesystem runtime, credential, Provider, Store, public SDK,
approval, Result or release acceptance is claimed.

Actual CLI activation requires the separately verified current Host evidence
permission; original/current custody or Store authority CID cannot substitute
for it. The unadmitted Catalog response-body persistence gap remains a distinct
pending contract. Neither gap is hidden by successful configuration admission.
