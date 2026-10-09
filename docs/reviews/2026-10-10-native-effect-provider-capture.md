# Retained Native Provider computation capture

## Change and Owner boundary

The existing physical Provider fixture stopped at admitted Preview/plan proof.
It now passes the original consumer Artifact, physical Provider observation,
checked Preview, original invocation and acquired/imported provenance through
the existing Result capture, dependency inventory, private Source payload,
complete Captured Run and encrypted Store custody Owners.

Independent rows are `[{"id":3,"record":"001000000000001"}]`, with a non-null
number `id` and a non-null string `record` limited to 15 UTF-8 bytes. The numeric
Program still expects `[{"id":3}]` and its original non-null number schema.
No expectations are copied from execution output.

The existing fault cases are reused with these real Provider rows:

- Failed persistence acknowledgement retains the same custody and execution
  reservation. Reopening SQLite authenticates the original encrypted bytes.
- Repeated persistence keeps the ciphertext and reservation unchanged.
- Private Source reader/cleanup failures retain their original owner and charge.
- Capture terminal-save acknowledgement loss does not return capacity early;
  reopening and retry settles it once and does not resurrect the capture.
- Wrong key, foreign Run, missing proof/source/dependency and late persistence
  remain refusals. Original input/pin/holding responsibilities remain separate.

The Capture holds computation and Source evidence, **not** target Preview
before/after. That independently admitted Preview is still a separate private
custody obligation. Store reopening retains the live execution Ledger and is
not evidence of Host or Coordinator restart.

## Fixed-source verification

Native source: `b3d48a15bf9d6d84f3b527c517e62c89f07585c8`.
The final submission adds only this evidence document to that code/runner SHA.

Retained receipts: `_build/native-effect-provider-capture-1791574635826/`.

Executed sequentially on that clean source:

```sh
moon fmt src/platform_native/remote_resident_source_compute_tests/effect_{provider_capture,provider_preview,transferred_artifact,result_capture,dependency_capture,source_custody,complete_capture,capture_custody}_wbtest.mbt
moon info --target native src/platform_native/credential_resource src/platform_native/salesforce_effect_preview src/platform_native/remote_resident_source_compute_tests
moon check --target native src/platform_native/salesforce_effect_preview src/platform_native/remote_resident_source_compute_tests
node scripts/test-native-salesforce-effect-preview.mjs --resident-preview
node scripts/test-native-salesforce-effect-preview.mjs --resident-effect-runtime-capture
git diff --check
```

Format, consuming interface, Native check and diff check passed. Provider
selection: **2/2 passed**. Existing Runtime completion/capture selection:
**1/1 passed**. The unchanged unfiltered file is not claimed successful.
Physical Provider receipt records **one read, zero writes**, and the outer
Native fixture checks Source/producer/consumer counts remain one.
Native whitebox executable SHA-256: `de7f04d2b0047a0cecfabbacb20ff41597864bde493d7ab78b06f77a9044f53c`.
This is a test executable, not a production Site binary.

The commands run under the existing bounded verification wrapper. The wrapper uses the pinned MoonBit toolchain and Node 24.21.0,
actual Native DuckDB, SQLite, curl and OpenSSL FFI, the existing verification
lock, nonzero-test checks, and an unchanged 180-second limit per selected run.

## Preserved failed checks

- `_build/native-effect-provider-capture-1791573724756`: the intermediate
  Provider composition ran 2 tests, 1 passed and 1 failed. An added assertion
  incorrectly expected target before/after inside Captured Run. The production
  Owner emits computation/source context; physical target values remain in
  Preview. The fixture now checks the admitted Source holding and keeps the
  exact physical Provider Preview checks at their correct boundary.
- `_build/native-effect-provider-capture-1791573852092`: intermediate dirty
  diagnostic, 2/2 passed. It is not the clean submitted-source evidence.
- `_build/native-effect-provider-capture-1791573984432`: clean
  `af2964ecd0f4e47e08c956abd1741ceb0b61ddf2`, all 11 retained-compute cases
  exceeded 180 seconds with no MoonBit summary. No pass count is inferred.
  The exact owned process group was subsequently absent; the same lock token
  and inode were checked before recovery. No signal was sent during recovery.
- `_build/native-effect-provider-capture-1791574281717`: clean
  `9d9d9fad0d903ceefbfde2aedb38851d9821b88d`, Provider 2/2 passed; the six-case
  `Effect*` selection exceeded 180 seconds with no summary. The wrapper stopped
  only its own remaining group and confirmed absence before releasing its lock.

The broad selections' timeouts remain unclassified failures; focused success
is not proof of their cause. Limits and fixture assertions were not relaxed.
The existing unfiltered suite remains available. The new focused selector runs
one existing Runtime completion/capture case; it does not remove other cases.

## Dependency and remaining work

Parent: #1187, published `92dfb632daa5257988c7a316690719c1930237fd`.
This is a test integration PR; all native production API changes are in its
parent chain. Final integration target is `main`, after those parents.

Not established here: target Preview durable custody, Cloud waiting commit,
Host/Coordinator restart, current approval, Effect mutation, unknown-write
reconciliation, final Effect Result publication, formal release of the Cloud
Run, or Preview acceptance. Source-free and existing effect-free Cloud evidence
are not substitutes for those obligations. Historical #88 custody is untouched.

Hosted CI remains disabled by instruction. No CI start/retry, merge, deployment,
1Password read, Site credential mutation or external Provider org operation was
performed for this unit. Test credentials are generated local fixtures; signed
runtime bundle bytes are the existing test component, not a production Site
binary. Native test executable digests must not be described as a formal runtime
package or deployed binary digest.
