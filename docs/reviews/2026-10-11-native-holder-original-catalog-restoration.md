# Native holder original Catalog restoration connection

## Scope and dependency

This private caller change follows #1470 (`cb09a3bf5eb975b37f0cf28c97187c99ae9c2249`), whose base is main `1887855e9bf867ba9c3abb724dc52ebe4be3daa1`. Merge #1470 first, then change this PR's base to main. The final destination is main, not the dependency branch. No submitted dependency head is rewritten.

Previously, a reconstructed Catalog caller could only enter the first-read path. The existing credential Owner rejects another claim for a saved use, but the caller did not restore the corresponding Catalog Store custody. This change connects the existing original-use query and original Catalog restoration APIs; it does not add an issuer, permission, recovery Owner, Ledger or stored format.

## Original evidence and restoration

Before an initial physical read, `HolderEffectCatalogReviewCustody` queries `query_native_credential_use` using its independently installed grant, exact original scope and use ID. That Owner admits the saved use against the original grant and checks authorization before and after its journal read. Candidate Catalog or transport bytes never supply an expected use CID.

An observed original use selects `Store.restore_effect_catalog_custody` with the original observation binding, resource, use CID, bounds, crypto library and key. The existing Store checks its authority, scoped holding, private evidence, response bytes, status, hash, Catalog admission and reservation. Its cleanup-only tombstone remains cleanup evidence, not an adoptable Catalog. The caller reuses the original restored custody and its existing persistence/readback and cleanup operations. No Provider request, Source acquisition, grant claim or second holding is made on this path.

Only the credential Owner's exact successful outcome with HTTP status 200 can reach Catalog adoption. Claimed, unknown, failed, missing or conflicting evidence stays pending. A repeated query must retain the same original use CID. Current evidence permission and original policy/context checks still fence adoption; custody inspection alone grants nothing.

The first-read path requires both the credential journal's exact missing-use result and the original Site journal's exact missing-Checkpoint-report result. A retained original report, corrupt report, missing dispatch, changed Site binding or failed journal read cannot hide a missing use by starting another Catalog request. This observation of absence is not read authorization: the existing physical-read Owner still performs its atomic claim and current authorization checks. This is not a proof that a replaced or lost credential database preserves historical absence, and this PR does not claim general lost-custody recovery.

## Cleanup and unresolved boundaries

When an original use has already been authenticated, cleanup can restore its exact Store custody without granting evidence disclosure. The same custody retries cleanup; reservations are not returned before the relevant Owner confirms it. A failed query or missing/corrupt original Store record retains the task's existing responsibility. Fixed local reasons distinguish use-observation and Store-restoration failure without exposing response bodies, settings or credentials.

One concrete boundary remains unresolved: the installed credential service's authorization callback requires the original live task/context. If the use was not observed before revocation or release, a subsequent cleanup-only query cannot be assumed authorized. This caller retains pending responsibility rather than reporting cleanup success. A connection to an existing authorized cleanup/reconciliation entrance requires separate contract review; no new permission or bypass is introduced here.

Raw, unadmitted Catalog response-body durability also remains a separate unresolved Store boundary. Restoring a successfully admitted Catalog does not turn a raw failed response into successful Catalog custody. Full approval-wait Review/Checkpoint reconstruction and public Effect completion are not claimed.

Production `effect_evidence_read` remains default false and unconnected. Run admission, Store authority, original/current identity, configuration snapshots and CIDs remain distinct from Host evidence-read authorization. The formal Cloud package cohort is unchanged.

## Validation

The matching private Native caller and the two new classification cases are checked with `moon check --target native src/cmd/native_remote_resident_site` under the existing non-Heavy worktree guard and 90-second bound. The tests are compile-only; no executable count is claimed. Formatting and `git diff --check` are checked under the same owned guard.

An intermediate diagnostic failed because a variable bound by a guard was referenced in the guard's failure branch. The diagnostic fix reads the retained task field in that branch; the original failure receipt is preserved independently of the corrected result.

No actual credential journal query, Native executable, crypto, physical Store restoration, Provider I/O, TLS, DO, public SDK, approval, Result, formal release or Preview acceptance has run for this change. Shared Heavy usage and producer builds are zero. Hosted CI remains stopped. Original success/failure receipts and retained artifacts remain unchanged.
