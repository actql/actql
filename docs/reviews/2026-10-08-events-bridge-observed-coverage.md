# Rows/Events claims require the four actually observed cases

## Problem and resulting behavior

The existing ordered typed Rows → Events → Rows claim names four authored cases,
while its single parameterized MoonBit test supplied only a successful test total
to the common receipt decoder. A count-only log could therefore be accepted
without independently identifying every case in the claim's finite scope.

The fixture now emits one fixed case observation after its existing intermediate
Events, final Rows, typed schema, ordered values, original Text, exact input
connection and retained Events discard assertions pass. The producer stores the
four observations in the existing execution record. The existing receipt sealer
and authenticated archive reader decode those original log bytes, and the Bridge
claim validator also checks the exact observed cases. No new action, harness,
Owner, model or scope is introduced.

The independent scopes are empty numeric input, nullable numeric payloads,
duplicate numeric payloads and a Timestamp carrying decomposed Unicode plus CRLF.
Missing, duplicate, reordered, widened, malformed or count-only observations are
rejected. A failed execution remains rejected even with four valid marker lines.
The markers identify completed assertions; they do not substitute for value,
schema, ownership or physical acceptance assertions.

## Inputs and integrated-main review

`proofs/events-bridge/observations.mjs` is a literal dependency of the shared
receipt decoder and is included in every Session action's shared input closure.
Changing its bytes changes the key; missing input remains unresolved. It is not
excluded just because an individual action does not call the Bridge branch.

Main commit `38f7801241a0a5ce32a2861a8603960016a29769` added two Node builtin
imports and changed the explicitly invoked pipeline `checkBaseline` function.
The old reviewed inventory digest no longer matched current main, making all
controlled closed-input fixtures unresolved. The accepted boundary now refers to
the current bytes, accompanied by a real source-delta regression: the eager
module prefix is unchanged after the two builtin imports are removed, the entire
current file equals that introducing commit, and importing the actual module
with filesystem and child-process effects refused performs no scientific I/O.
The snapshot/hash code and eager declarations are unchanged. Unreviewed future
inventory edits and unresolved runtime input still prevent reuse.

This is a bounded import-time/source review; it does not prove complete runtime
isolation or classify the explicitly invoked history checker as effect-free.
Historical declarations and source witnesses remain immutable.

## Local validation

The implementation acceptance source is the clean commit
`4fb646eceeb18d9bb0a6ae8ddedfc7511c911568`, based on main
`f2ceac7e0c673780b053b9a323e76a03c152e09a`.

Working-diff preparation: 79/79 Node tests, zero skips, using the existing
bounded/nonzero wrapper:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  proofs/events-bridge/evidence.test.mjs \
  proofs/ci-evidence/inputs.test.mjs \
  proofs/ci-evidence/current-input-obligations.test.mjs \
  proofs/ci-evidence/execution-recipes.test.mjs \
  proofs/ci-evidence/acceptance.test.mjs \
  proofs/ci-evidence/session-module-boundary.test.mjs
```

That record is `run-epF3BG` / `focused-test-dhbnSC`: it records the dirty
working tree on the pre-implementation base and is not relabelled as a clean
commit execution. The earlier 63/74 preparation failure exposed the stale
inventory boundary and is retained locally. An earlier heavy check attempt was
refused before executing any test because another owner held the heavy lock;
this is not an acceptance failure.

The clean fixed-source acceptance uses the existing worktree guard for the
focused JS/Node checks, normal process isolation, and the cooperative heavy lock
for the separate actual history scan. The selected commands are:

```sh
moon test --target js \
  src/query_integration/events_bridge_evidence_wbtest.mbt --deny-warn
node --test --test-concurrency=1 \
  proofs/ci-evidence/receipts.test.mjs \
  proofs/ci-evidence/final.test.mjs \
  proofs/ci-evidence/current-input-obligations.test.mjs
node proofs/relation-pipeline/history.mjs --write
```

The MoonBit and Node steps run through `runFocusedTests` with the checked-in
nonzero guards. Receipt tests construct independent ZIP/API fixtures and require
missing case rejection even if the receipt, observation and archive hashes agree.
Final tests execute the pinned Lean checker and verify its certificate rather
than substituting an unconditional successful checker. The source-parent-blob-
mode history step validates the actual repository, not a synthetic Git fixture.

Fixed-source evidence before the history scan:

- `run-HVS87D`: the actual JS fixture passed 1/1 and emitted all four exact case
  records. Cold compilation plus execution took 199.273 seconds. The following
  Node step was terminated at the shared 240-second budget; the whole attempt is
  **timeout**, not passed. Its successful JS step and raw bytes remain original.
- `run-J09g2D`: the independently budgeted Node selection completed 33/35 with two
  Lean `ETIMEDOUT` failures. The 24 receipt tests and five actual-input tests
  passed. The four other final-certificate tests passed, including the 30-action
  mixed plan, non-main origin refusals and related-input full-fresh fallback.
- `run-A459D8`: only the two previously timed-out final tests were rerun with the
  same pinned Lean, 30-second checker limit, source and acceptance assertions.
  Both passed, with zero skips. This includes the full 30 fresh obligations and
  the missing Bridge/target-swap rejection checks. The earlier failed record is
  not overwritten or presented as a successful single 35-test run.

Thus every one of the 35 selected fixed-source Node cases has a successful
observation across the original and narrowly selected retry. The raw consumer
requires the retry's two successful names to equal the original two timed-out
names, while preserving the failed attempt. No successful JS or other 33 Node
cases were repeated for this purpose.

The JS raw-log readback also runs through the production receipt observation
interpreter, including four separate missing-case rejections. Three actual
query-integration JS artifacts (46,746,340 bytes total) are copied by content
identity and read back. This binds the compiled witnesses to the clean source,
authored assertions and actual observed marker bytes under the pinned compiler.

The actual repository history scan `run-V4PY77` passed on the clean acceptance
source in 186.878 seconds: 267 declarations, 217 integrations, 27 supplements,
one change completion and 89 protected files. Its original composed manifest
retains `sourceRevision`, parent identities, bytes and modes.

The readback consumer preserves the failed whole-attempt status separately from
complete raw output, verifies the exact four observed cases, the 35 independently
successful Node case names, all three compiled witnesses and the history source.
The immutable archive is
[`evidence/2026-10-08-events-observed-coverage-4fb646ece.tar.gz`](evidence/2026-10-08-events-observed-coverage-4fb646ece.tar.gz):
63 members, 496,070 bytes, SHA-256
`4f79cd4cfe92225832b3c8ebb2737eeaf00f944e6fdebc1225f7110ca02a33a3`.
Every member was decoded and compared byte-for-byte with the original. The archive
contains the local report, raw logs, commands, source witnesses and binary digest
references; the 46,746,340 bytes of compiled artifacts remain in the owned local
`.artifacts/events-bridge/observed-coverage/binaries/` custody.

The publication commit only adds this review note and the original evidence
archive after the tested source. It does not relabel the receipt's execution SHA
or repeat successful tests solely for documentation. No changed input at this
boundary was found between the adopted main and the then-current
`0ed193460b2c220e78dc840b3fde23661fc926b9` main.



## Preserved obligations and remaining work

The original four semantic cases and their authored expected values are
unchanged. Existing shared Session, adapter and operation correspondence tests,
16 exact-type audited Bridge/composition laws, complete target coverage and
mutation obligations remain required by the normal full family.

This selected execution does not constitute a fresh complete Session family,
Wasm/Native Bridge execution, physical allocation bound or universal refinement.
Controlled ZIP/API fixtures and an executed Lean checker are not authenticated
Hosted Actions originals. Cross-revision qualification, ordinary PR reuse of
`mutations-js`, related-input fresh fallback in actual Actions and net savings
remain the separate deferred unit. No reuse policy, CI trigger, job selection,
mandatory action inventory or performance result is changed here.
