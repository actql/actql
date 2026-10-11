# Original Checkpoint Store restoration

## Existing boundary

The existing `Store.restore_effect_checkpoint_custody` takes the original continuation body as an argument. This supports a still-live retention Owner reopening its Store and finishing partial persistence. It cannot supply lost process-local body bytes to a reconstructed caller. Passing a regenerated continuation or candidate transport body would not establish original custody.

`restore_confirmed_effect_checkpoint_custody` connects the existing Store machinery to an independently selected original `SealedCheckpoint`, such as the one admitted from the original dispatch's Site journal report. The caller must retain that trusted selection and its Host disclosure authorization. A wire-supplied Checkpoint, CID, snapshot or Store authority is not permission to reveal private evidence or execute an Effect.

## Exact original read

The new entry requires the same Store authority and original Effect Run-unit Checkpoint. It reads the original continuation row at that Checkpoint's physical holding, requires the original active revision, and opens it with the existing `continuation_record` AEAD role and original continuation CID. Retired evidence returns `RecoveryRequired`; missing evidence returns the existing database error.

The plaintext must fit the unchanged Store record bound, match the sealed original continuation digest and decode as UTF-8. No normalization, candidate expected value or new identity domain is introduced. It then uses the existing restore method and confirms both original continuation and Checkpoint records before returning the existing custody type. Missing paired evidence is not allowed on this confirmed-read entry. Concurrent retirement or conflicting readback remains an error; this does not claim an atomic snapshot across all Owners.

No persist, database insertion, capacity reservation or Provider request occurs. Preparing existing physical handles may seal an in-memory envelope as the existing restore method already does; stored ciphertext is not replaced. The existing `confirm`, `retry_cleanup`, tombstones and capacity responsibility remain unchanged. The original unfinished-persist method is retained for its distinct use, rather than relaxing this new read's requirements.

## Connection and remaining work

This is the required original-body restoration seam, not full Resident Review reconstruction. The original Run/materials, retained consumer input, checked binding, captured Run, Preview, request, authority and Ledger still require their own existing Owner admissions before the returned body can be used for approval/reconciliation. A reopened Store alone does not restore those process-local values or grant current Reviewer/write authorization.

Production evidence-read remains default false. Raw unadmitted Provider response durability and cleanup-only use reconciliation after authority loss remain unresolved. Cloud's formal package cohort is unchanged. Approval-wait restoration, Provider execution, public Result and formal release remain completion obligations for Cloud #138.

## Validation scope

Five selected portable JS cases execute the actual plaintext admission helper: original values and line endings, normalized/substituted bytes, foreign digest, unchanged byte bounds and invalid UTF-8. These are plaintext admission tests, not encrypted Store or Provider evidence.

The existing real Native continuation/Checkpoint fixture is extended to check partial pair rejection, original-body restoration without caller body bytes, unchanged Store reservation, foreign authority, wrong key and retired evidence. These additional assertions are compile-only until the separately allocated physical verification window. The matching Native fixture and resident caller are type-checked; no Native executable or producer is built or run.

The affected package interface is generated with the existing tool for JS, Wasm and Native. Changed files are formatted and checked for whitespace. Non-Heavy guarded commands retain separate receipts and release their exact owned groups/locks. Hosted CI is stopped. Intermediate type and command-selection failures are retained, and do not count as executed passing cases. Public Cloud, DO, TLS, approval, SDK, Effect, Result, recovery and release acceptance are not claimed.

## Dependency

This is an independent main-targeted change based on `1887855e9bf867ba9c3abb724dc52ebe4be3daa1`. It does not modify or depend on the submitted #1470/#1472 holder caller heads. Their future restoration caller can consume this API after its normal main adoption.
