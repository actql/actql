# Acquired Effect common Host integration checkpoint

Implementation checkpoint: `7d266e73bcb6a58c7c545db448afedba9a7d6faf` on
`feat/source-effect-run`. This document does not assert that the branch has
been pushed or that Linux CI has passed; delivery records must name the
actual pushed HEAD separately.

The implementation checkpoint above is now pushed to
`origin/feat/source-effect-run` for D's connection work, not merge approval.
Independent review reproduced two remaining P2 issues: per-payload damage
prevented the entire Store from opening, and a crash after capture holding
commit but before the private record stranded cleanup responsibility. C
owns both fixes; D must not weaken rejection tests or implement workarounds
inside Salesforce. Final acceptance must use C's subsequent correction SHA.

## Working route and responsibility

The reference Site test uses public HTTP, real DuckDB acquisition, two
Stages, two Effect members and four writes. It reaches durable approval,
Host restart, approval, execution and Named Result. Response loss preserves
unknown without resend. Cancellation and rejection after restart reclaim
upstream-only payloads. This is not real Salesforce acceptance.

C owns compiler, common Host, Checkpoint and the APIs below. D connects the
Salesforce adapters to these existing owners, without copying their logic.
Do not wait for B's Frontend integration.

## Adapter connection points

1. For an Effect acquisition, use
   `clientProgramIdentifyCapturedEffectSourceRelation`, not the ordinary
   non-retaining Source identity entry. Retrieve canonical Relation/schema
   bodies with `clientProgramCapturedSourceDependencyBodies` on that same
   live owner. See `captured-duckdb-source.mjs` for the common call sequence.
2. Pass the supplied publication Plan's `localEvidenceContext` into
   `preparePinnedEffectSourceSet`. Its dependency work is bounded: allow
   enough `maxGroupingWork` for checked local Results and member matching,
   not only the former Values member grouping. Do not remove the limit.
3. If `sourceSet.dependencies` exists, call
   `retainPinnedEffectDependencyPayloads({sources: sourceSet, execution,
   store, storedResults, control, runDefinition: plan.runDefinition})`
   before committing member holdings. This transfers prepared dependency
   payload custody to the existing completed Result owner. Validation
   failure leaves custody with the caller; successful adoption uses that
   owner's release/retry path.
4. Select Effect payloads through `sourceSet.members[index].payload`.
   `sourceSet.payloads` also includes upstream-only Results. Bind Preview
   inputs to the checked member's actual Stage/Unit, not literal index zero.
   The acquired Plan carries its original `invocationOwner`; do not issue a
   substitute Invocation. The common installed continuation now records and
   verifies the exact `unit_id` before claiming resume.
5. Continue using `issueCompletedEffectfulComputationEvidence` and the
   existing recovery/publication owners. They persist and verify dependency
   inventory, bodies and physical bindings. No provider-specific inventory
   issuer, fallback fetch or recomputation is needed.

The executable reference is `prepareReferenceCapture` in
`adapters/host-node/remote-checkpoint-host.test.mjs`.

## Durability, failure and compatibility

Before capture completion, acquisition/Compute are preparation, not a
recoverable approved input. Required upstream Results are retained before
their final Compute consumer releases them. After exact member/capture
holdings and the private capture record commit, the common owner can
publish approval waiting and relinquish temporary custody. A failed commit
does not establish a resumable approval.

Recovery uses saved input/Preview. Current commit permission, installation,
Mapping and target checks remain separate from Source reacquisition.
Missing or foreign dependencies reject without repair. Unknown writes keep
their Ledger and capture evidence; successful rows are not resent.
Cleanup failures retain existing owners rather than starting Compute again.

This is the approved incompatible coordinated 0.1 change. The semantic
dependency contracts, pins and independent vectors changed together. The
private capture additionally requires `effect_dependency_payloads`; the
private continuation requires `unit_id`. Old missing fields are not filled
in, and saved data is not rewritten.

## Reproduction and evidence

Use pinned Node/MoonBit and installed repository dependencies. Generate
ignored runtime payloads from this source; do not copy another branch's
bundle.

```sh
npm run build:runtime-packages -- local-node
node --test --test-name-pattern='acquired Effect' adapters/host-node/remote-checkpoint-host.test.mjs
node scripts/test-acquired-effect-computation-probe.mjs
node --test adapters/host-node/client-program-bridge.test.mjs adapters/store-local/publication-store.test.mjs adapters/host-node/installed-effect-site.test.mjs
```

Local evidence: the three-file suite passed 101/101. All four Compute probe
scenarios passed with one initial actual Compute call and zero restart
calls. Core JS passed 6,962; Wasm passed 6,959; native passed 7,021. Native
test execution took 764.4 seconds; its check step passed separately.
Specification validation and generation correction are recorded in
`2026-09-29-source-effect-dependency-contract.md`.

Still pending: final Client/Host/Workers/lint gates, pushed-SHA Linux CI,
Salesforce adapter acceptance, acquired-path Embedded/outside-repository
tarball acceptance, and additional acquired dependency cleanup/expiry fault
coverage. D's real-org evidence remains separate and is not claimed here.

## Post-handoff verification and P2-1

The Client gate's Node suite passed 261/261. Its packed smoke was deliberately
terminated to prioritize the reproduced P2 fixes; the Client job is not
green. This interruption is not a demonstrated product failure, and the
successful Core targets need not be repeated for a Store-only correction.

Store startup now validates the holding records and index ownership links
without scanning every payload. Access, commit and consumption still verify
payload integrity; metadata-format and authority failures remain distinct.
New real-Store tests first reproduced missing/corrupt input preventing open,
then passed with healthy input readable and damaged input rejected without
discarding its holding. The entire Store test file passed 64/64.
Two-Run public HTTP acceptance now passes for deletion and one-byte damage
of an upstream-only dependency. The healthy Run's Named Result remains
readable before and after answering the damaged Run's Checkpoint. The latter
rejects with `PublicationObjectMissing` or `PublicationObjectCorrupt` before
provider recovery, sends nothing and retains its holding records.
The module probe now wraps both the real Source capture entry and the real
Effect Compute entry, forwarding to the original implementations. All six
scenarios (success, unknown, cancel, reject, missing, corrupt) passed with
one initial Source/Compute call each and zero restart calls. This is not
best-effort telemetry and introduces no public instrumentation API.
At the initial handoff, the unfinished capture crash-window P2 remained
unresolved. Subsequent implementation and evidence are recorded below;
neither P2 has final pushed-SHA CI acceptance yet.

## P2-2 process-stop reproduction

The standalone `scripts/test-effect-capture-crash.mjs` regression intentionally
asserts the required cleanup outcome, not the current leaking behavior. Until
P2-2 is corrected, the first two commands below fail. They are not green-gate
evidence. Each child executes the actual acquired bridge fixture and exits
with code 77 immediately after the selected real Store commit, bypassing
normal exception cleanup. The parent reopens that Store in a fresh process.

```sh
node scripts/test-effect-capture-crash.mjs effect-source
node scripts/test-effect-capture-crash.mjs effect-capture
node scripts/test-effect-capture-crash.mjs publication-private
```

Observed against the `f0e90ff5d` implementation:

| Stop after | Recovery | Retirement | Remaining holdings / payloads |
| --- | --- | --- | --- |
| First Effect source holding | Capture unavailable | Returns false | 1 / 1 |
| Capture holding | Capture record missing | Capture record missing | 2 / 2 |
| Private capture record | Completed capture | Recovered owner cleanup succeeds | 0 / 0 |

The successful control releases the prepared owners acquired by recovery;
otherwise the harness itself would retain a payload and prevent Store close.
Neither incomplete case is admitted as a completed computation. The earliest
failure precedes any Checkpoint: enumerating only terminal Checkpoints cannot
discover all unfinished capture custody. Merely swapping the capture holding
and private-record writes also leaves the earlier member-holding window.

The correction must durably associate exact member/capture holding custody
with its Run before the first holding transfer. Completion evidence remains
separate. Recovery of incomplete cleanup must use the existing Store owners
and original Run state, must not authorize execution, and must not retire
evidence needed for unknown writes. These three probes cover post-commit
stops only; before-commit, shared-object, cleanup-failure and public Host
recovery coverage still remain to be implemented with the correction.

The first correction records bounded physical cleanup custody in the existing
Store before member holdings commit and extends it before the capture holding
commits. It binds the admitted Run Definition, Store authority and exact
holding records. The private completed capture takes custody only after its
record commits; this inventory is not execution or approval evidence.
Retirement validates every surviving holding before deletion and keeps the
inventory until all deletions finish. Limits are 4,096 holding records and
the smaller of 16 MiB and the Store's object-byte limit per inventory.

All three process-stop commands now pass locally, including an unrelated
holding sharing the interrupted capture's payload and a real deletion
directory-sync failure followed by cleanup retry. Incomplete captures remain
unavailable for execution. This closes the explicit common retirement path,
not the full P2 acceptance: Host discovery/retirement of pre-Checkpoint
custody, registration failure boundaries and final regression gates still
need connection and verification. Do not use this result as merge approval.
The touched bridge, installed Effect and Publication Store test files passed
103/103 after this correction. No new Core run was needed for these JavaScript
custody changes; final Host/Client jobs and pushed-SHA CI are still pending.

The public Host now discovers pre-Checkpoint custody through the same Store
and checks the original request journal's exact Run and authority scope. Live
dispatch owners, existing Checkpoints and completed private captures remain
excluded from this incomplete-capture sweep. Failed deletion remains in the
existing Store cleanup inventory and Host shutdown retries the same owner.
It never marks the interrupted Run successful/failed or reserves another
Compute start: the original request remains `needs_reconciliation` with
`reconcile_run/execution_unknown` even after physical cleanup.

`scripts/test-effect-capture-host-crash.mjs` drives actual HTTP processes and
the reference adapter. Stops before/after the member holding, before/after
the capture holding, and before the private record all recover physical
custody with zero restart Source/Compute calls and zero writes. Another Host
reopen retains the same request. These cases are now connected to Client CI;
local acquired/unknown/cancel/reject/corruption HTTP regressions passed 10/10.
No Linux result is claimed yet.

## Completed-record ownership handoff correction

The completed private record no longer removes the cleanup inventory by
itself. The standard completion owner transfers custody immediately before
physical dispatch, after apply establishes current admission and durable row
intents. Its wrapper snapshots the publication and dispatch references before
awaiting authorization, and checks cancellation after the custody sync.
This transfer confers no authorization and changes no Ledger outcome.

Waiting Checkpoints keep the inventory: their existing durable record
protects it from pre-Checkpoint retirement. Resume transfers custody before
dispatch; cancellation/rejection retires it with the exact completed capture.
Normal explicit owner release also discharges the inventory, including a
capture released before a Checkpoint was created. Thus missing Checkpoint
alone still does not authorize deleting execution-owned or uncertain evidence.

The actual public-Host stop immediately after the private capture commit now
passes as the sixth save boundary: the original Run remains unknown, cleanup
finishes, and restart does not reacquire, recompute or write. The three-file
bridge/installed-Effect/Store regression passes 103/103. The six actual
Source/Compute probes pass again for success, unknown, cancel, reject,
missing input and corrupt input (one initial call, zero restart calls).
These are local implementation results. Final Host/Client/Workers/lint/spec
jobs, pushed-SHA CI and the acquired Embedded/packed acceptance remain open.

## Client gate and recovered-factory diagnosis

At `181add3f5a28b4bca113507f9e0641180d4f62e1`, the Client gate passed
263 Node tests, packed Node/browser smoke, packed HTTP Checkpoint acceptance,
native Client mTLS, and packed Embedded Checkpoint acceptance. The Salesforce
job failed (268/270); the subsequent Compute/crash steps did not execute.
One failure is the recovered-factory fixture; the other still needs diagnosis.

The recovered-factory failure was reproduced before changing its inputs.
The actual execution callback rejected with
`InstalledEffectContinuationMismatch`: the fixture omitted both the saved
Unit ID and the Checkpoint's run-unit subject. Its HTTP submit handler had
already accepted the Run and was awaiting `start`, so the SDK correctly
reported `SubmissionUnknown`. This was not an HTTP acknowledgement loss.

The fixture now uses the official compilation owner's Unit ID in both
bindings. Missing and foreign Unit IDs must still reject before any resume
claim or dispatch; valid recovery must publish all four rows. The focused
test passes with these assertions. No production refusal was relaxed.
This diagnosis is separate from capture cleanup and the three pending
Run-outcome classification corrections requested after D's re-verification.
