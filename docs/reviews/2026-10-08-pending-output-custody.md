# Preserve unfinished Output custody during holder reconstruction

## Observed product failure

The actual two-task Worker/Native acceptance used Cloud source
`427c7a0227b95fd6ffaa9fa0119c7b2222df450d` and formally adopted OSS source
`ad7fd0f88791a3fec4cd0a5164699a7048fbcda5`. Source, producer and consumer
executed once each. The original Output Transfer was admitted, but had not
committed when the bounded invocation stopped. The observed HTTP 201 was the
Transfer admission response; it does not establish a chunk upload.

An attach-only continuation of the same Run observed Native startup reclaiming
one Output intent before restoring its consumer holder. Subsequent exact Output
requests failed with `intent`; Cloud observation repeatedly returned
`TransferNotCommitted`. No replacement Run or Compute was submitted.

The existing orphan reclaimer treated an absent holder and an exclusive executor
slot as permission to reclaim every pending Output payload. Completing that
intent then prevented its original continuation. This behavior is also present
at the fix's main base, `97a98b27edaee19786217093aacb3e1768c35892`.

Original failure evidence remains in `completed-successor-partial-output-recovery-defect.json`
and the original acceptance journal, Transfer Store and command receipts. They
are retained; this fix does not declare that historical Run recovered.

A subsequent public SDK cancellation of the same original Run confirmed both
tasks' release through their existing Owners and reclaimed the Native temporary
resources without another executor entry. The Cloud-side Output Transfer still
requires cleanup. A read-only reconstruction through the installed Owners finds
the exact original request's wake retained and pending; an earlier audit's
hard-coded request name incorrectly reported that wake absent. Neither Native
resource reclamation nor Run cancellation proves the remaining Transfer settled.

## Ownership boundary

The exclusive slot proves that no holder can still write the payload. It does
not prove that the completed task's Output responsibility ended. Reclamation now
also requires the matching original dispatch's existing journal record to be in
`CleanupReleasing` or `CleanupReleased`, as issued by the common release Owner.

The lookup binds both original attempt and dispatch identity. Unreadable,
foreign or missing ownership remains pending. The existing publication Store
still confirms physical cleanup before intent completion and capacity return.
No new state, protocol, ledger, identity or public API is introduced.

## Focused physical regression

Command, using the pinned MoonBit toolchain and Node:

```sh
node scripts/test-native-core.mjs --strip --deny-warn --jobs 2 \
  src/platform_native/remote_resident_host/stopped_retained_cleanup_native_wbtest.mbt \
  --filter 'pending Output survives holder loss until formal release and retries the same cleanup'
```

Result: **1 executed, 1 passed, 0 failed**. The bounded command receipt is
`pending-output-custody-native-Vc0o7A`. Source and test blobs are recorded in the
PR validation; the test ran on the uncommitted implementation before publication.

The test uses real SQLite journals, publication payload files, Store cleanup
Owners and common-Owner-issued dispatch transitions. Its fixture does not claim
to execute Source or Compute. It verifies:

- Before formal release, orphan reclamation leaves the sealed payload, its
  32-byte reservation and its original pending intent intact.
- Closing and reopening the original journal and Store preserves that custody.
- After formal release begins, an active reader produces the existing typed
  `ReaderBusy` refusal. Reservation and intent stay held.
- Closing that reader permits retry to reclaim the payload, complete the same
  intent and return its reservation. A repeated retry returns nothing twice.
- A foreign attempt cannot supply reclamation authority.

Earlier compiler and fixture failures are preserved in the local evidence; they
are not counted as successful checks. Formatting and `git diff --check` passed.

## Remaining acceptance

This PR protects unfinished Output custody; it does not add continuation of an
uncommitted Output Transfer or resurrect an already-reclaimed historical payload.
The existing committed-destination report recovery is a separate path. Formal
Cloud adoption, the original unfinished Run's recovery disposition, end-to-end
interrupted Output continuation, injected cleanup acceptance, required CI and
actual Preview acceptance remain outstanding. Existing gates are not weakened.
