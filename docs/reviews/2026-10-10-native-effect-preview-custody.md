# Original Native Effect Preview custody

## Change and responsibility

The completed Captured Run contains computation/Source evidence, not the target
Preview's before/after. Retain that original Preview independently, using the
existing private Preview holding identity and authenticated encryption domain.
The Native Resident caller first validates its original computation/Preview
chain with the common publication Owner. Admission binds the original wire to
its Run, authoring identity and actual Store authority before allocation.

The existing Store transaction, capacity reservation, encrypted readback and
cleanup mechanism now serves separate typed Capture/Preview factories. Capture
storage namespace, authenticated domain, terminal wire and callback names are
unchanged. Preview uses its own scoped holding, terminal and exact reservation.
No alternate Ledger or holding identity domain is introduced.

The caller reserves the existing execution Ledger before persistence and returns
the same custody when a Store operation is uncertain. Repeated persistence reuses
saved ciphertext. The common Preview Owner requires the original canonical wire;
foreign scope/body, noncanonical wire and limits are refused before persistence.
Saved bytes are authenticated against the original identity and exact body.

Explicit retirement confirms the durable terminal before returning Store and
execution reservations. Lost cleanup acknowledgement retains both responsibilities;
retry returns them once. A tombstone prevents late persistence from reviving the
same Preview. The trusted caller must first discharge Preview obligations; neither
Run termination nor physical resource disappearance is proof of that discharge.

Preview, computation Capture, Source payload, receiver, borrow and public Named
Result remain separate owners. Reopening SQLite preserves the original live
execution Ledger; this does not establish Host/Coordinator restart recovery.
Saving Preview does not grant waiting, approval, current authority or apply rights.

## Fixed-source verification

Code/test source: `6b05273854a2beaeb4c3c93dfff651c5d4276f58` (clean).
The submission adds only this evidence document after that SHA.

Receipt directory: `_build/native-effect-preview-custody-1791576004226/`.

Executed sequentially under the existing owned verification lock and bounded,
nonzero-test wrappers, pinned MoonBit and Node 24.21.0:

```sh
moon fmt src/platform_native/publication_store/effect_capture_custody_native.mbt src/platform_native/publication_store/effect_capture_custody_unsupported.mbt src/platform_native/publication_store/store.mbt src/platform_native/remote_resident_host/source_compute.mbt src/platform_native/remote_resident_host/effect_preview_custody.mbt src/platform_native/remote_resident_source_compute_tests/effect_preview_custody_wbtest.mbt src/platform_native/remote_resident_source_compute_tests/effect_complete_capture_wbtest.mbt src/platform_native/remote_resident_source_compute_tests/effect_capture_custody_wbtest.mbt src/platform_native/remote_resident_source_compute_tests/effect_provider_capture_wbtest.mbt
moon info --target native src/platform_native/publication_store src/platform_native/remote_resident_host src/platform_native/remote_resident_source_compute_tests
moon check --target native src/platform_native/publication_store src/platform_native/remote_resident_host src/platform_native/remote_resident_source_compute_tests
moon check --target js src/platform_native/publication_store
node scripts/test-native-salesforce-effect-preview.mjs --resident-preview
node scripts/test-native-salesforce-effect-preview.mjs --resident-effect-runtime-capture
git diff --check
```

Formatting, consuming Native interface/check, JS unsupported-target Store check
and diff check passed. Actual Native Provider selection: **2/2 passed**. Existing
numeric Runtime completion/capture case: **1/1 passed**. This is not the unfiltered
retained-compute suite or portable runtime execution coverage.

Actual Native DuckDB, SQLite, curl and OpenSSL are used. Physical Provider receipt:
`scratch/native-salesforce-target-9putpK/physical-receipt.json` under the receipt
directory, **one read and zero writes**. The outer fixture retains independent
rows/schema and checks Source, producer and consumer entry counts remain one.
The original target has `Count__c: 7` before and intended `Count__c: 3` after;
exact Preview wire readback preserves its guard/version and typed identity.

The new fault acceptance runs with the still-retained computation in the same
actual SQLite Store. It checks committed Preview persistence acknowledgement
loss, authenticated readback, wrong key/role refusal, identical retry, foreign
Run/authoring/Store/target refusal, limit/noncanonical refusal, terminal-save
acknowledgement loss and cleanup retry. Preview cleanup returns only its own
reservation while computation remains confirmable/charged; subsequent computation
cleanup returns its separate reservation. Repeated cleanup does not return either
reservation twice. Late persistence cannot resurrect retired Preview evidence.

Retained whitebox test executable SHA-256:
`22d6de3fea013d4f90cb953d5b70b1b439dcb77f570e0e0a711f34714b39710c`.
This is a test executable, not a formally adopted production Site binary. Signed
runtime bundle components in the fixture remain explicit test components.

## Preserved failure

`_build/native-effect-preview-custody-1791575776026/`, clean code
`05e15172a3e2f46bd8ac373f4529827fab8136e1`, aborted with SIGABRT and no MoonBit
summary; no test pass count is inferred. A new negative fixture incorrectly
unwrapped admission of trailing-newline Preview wire. The existing common Owner
explicitly refuses it as `PreviewShape(InvalidWire)`. The test now asserts that
exact refusal without changing product validation. The original failed SQLite
contains both active reservations (Capture 61,476 bytes, Preview 4,684 bytes);
its database, logs and receipt remain protected. Successful acceptance at the
later fixed SHA does not erase this failed run.

The earlier #1189 six-/eleven-case 180-second timeouts remain unclassified.
The small selected passes do not resolve those failures or justify raising limits.
The existing unfiltered suite remains available; the 180-second runner limit and
nonzero-test checks are unchanged.

## Dependency and incomplete execution connection

Parent: #1189, published `ebae4f17953f5ebe6c8ecd3a5293b302a852b4c3`.
Current PR base is `feat/native-effect-provider-capture`; final destination is
`main` after the published Native parent chain. Formal Cloud adoption must use
its merged source/cohort and production binary, not this test executable.

Remaining: the complete private recovery inventory, committed Cloud waiting
transition, Host/Coordinator restart, current approval, real Effect execution,
unknown-write reconciliation, final Cloud publication/release and Preview
acceptance. These are subsequent connection work in the existing F goal, not
proved by custody success. Historical #88 original Run responsibilities are
unchanged and cannot be closed by another Run's success.

Hosted CI remains stopped by instruction. No CI start/retry, merge, deployment,
1Password read or external Provider org operation was performed for this unit.
