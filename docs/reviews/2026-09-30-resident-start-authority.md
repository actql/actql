# Resident Site start-time authority — PR #72

## Start boundary and custody

Receipt and holder reconstruction use the Site's current clock. Reconstruction
is not the final start permission: SQLite claim/state persistence and runtime
preparation can wait. The resident Host installs a mandatory runtime start
guard which reuses `check_resident_run_current` on the rebuilt Run and its
authorization, using a fresh clock reading after the exclusive claim and
Running persistence, before `RuntimeExecutePhysical`. It checks again after
the executor-entry evidence hook, immediately before the physical call.
The evidence hook is not an authorization callback.

Receipt expiry rejects before durable acceptance. After receipt, the Host
structurally rebuilds the exact saved Run without returning early on lifetime
rejection: an expired Accepted record otherwise remains the retryable queue
head forever. It latches that rejection, acquires the existing exclusive start
claim, and uses `StartAuthorizationRejected` and the stopped-before-start
failure/cleanup progression. Provisioning/Running are control records, not
evidence of an executor call. The terminal record is Failed/NoEvidence/
CleanupReleased/no-material/no-quarantine; it is neither Cancelled nor erased.
The parent removes the head only after its existing durable-owner inspection.
The Host exposes `Refused(NotCurrent)` while retaining a runtime whose close is still pending.
The runtime, bundle, Site operation and slot are not freed by a clock failure;
their existing owners confirm cleanup. No claim authorizes re-execution.
Structural reconstruction and temporary Store/journal failures are not
reclassified as lifetime rejection. Failure persistence after claim can itself
fail: the existing runtime keeps its cleanup owner and the holder keeps the
slot, retrying close only until the terminal state and cleanup are durable.

`execute_resident_attempt` now takes `() -> String` rather than a fixed clock
string. The runtime adds `guard_executor_start` and a typed rejection. Both
generated interfaces and the exhaustive application-Site issue formatter are
updated. These native interfaces change together; SDK, wire, CID algorithms
and saved formats are unchanged by this correction.

The process regression advances a **local test clock**, not a dispatch clock,
at observed receipt, before-reconstruction and post-claim boundaries. Its
post-claim check reads the exact durable claim before advancing time. The three
boundary cases use separate journals; a further regression deliberately uses
the **same Site and journal** for an expired accepted head and a longer-lived
successor. It checks real executor entries (head zero, successor one), durable
failure/cleanup, Output release/capacity, and exact redelivery without another
holder, entry or terminal revision change. A real SQLite write lock also
prevents expiry failure/cleanup persistence after claim; the test checks the
live holder, retained claim/slot and zero entries, then removes the fault and
requires durable Failed/CleanupReleased without restarting execution. The
normal CLI path always reads the system clock; missing/invalid test-clock bytes
fail closed. This is controlled-clock fault injection, not evidence of live
mid-execution revocation. All three cases require zero executor entries and
no Output intent/payload reservation; acquired resources must finish cleanup.

## Fixed Run CID: independent preimages

The failed CI run `36681549358` tested merge checkout
`7c0a29dcc6239df4d864fb27289fb4d245fd38f3`, not merely the branch source
`d2b773d948753c46a6d01d38c646eda7ca2defc2`. Its main parent included #63.
The grammar manifest changed from `15a180c7…` to `c34717…`, and the AoA contract
from `4b6f51d5…` to `bfb017…`. These normative preimages feed the bound invocation
template, executable Plan, compiled Plan and Run; the fixed Program CID,
logical pipeline and capacity-witness inputs did not change.

`scripts/client-values-run-materials-vector.test.mjs` independently assembles
the two-row Values bodies and canonicalizes/hashes them with Node crypto. It
imports no product compiler/issuer or generated output. The same construction
reproduces the previous template/Plan/Run vector, then rehashes the checked-in
grammar and AoA bodies and derives the current Run:

```text
old Run: sha256:e80cf974a2d99757867e3d087e88f48245aab36df049d0dd6959d264ec6be7b5
new Run: sha256:6c8f2f917142d144e0c7f3d5730884d8a40ded58a6adf288eedf0da328363169
```

The MoonBit fixture retains its literal assertion. CI executes the independent
vector before Core tests. This is an expected-fixture update following the
inherited normative changes, not a new CID rule or a compatibility claim.

## Available revocation controls and freshness limits

| Material/control | Actual reflection boundary | Not guaranteed |
|---|---|---|
| Bearer credential file replacement/removal | Native HTTP rereads the configured credential file for each request; invalid/missing bytes reject the next request. Server-side acceptance also determines that request. | Retroactive cancellation of an in-flight request or physical executor. |
| Local delegation CLI configuration (authority, Site/generation, runtime, Connector, grant, issuer, budget) | Each control/holder process constructs and checks its configured delegation. New processes use their supplied configuration. | A live hot-reload or immediate running-process delegation-revocation API: none is provided. |
| Runtime bundle `drain`/`activate` | These persist catalog changes; existing active-component checks reload the catalog when admitting work/acquiring components. | Preemptive physical stop of already-running code. |
| Run validity / authorization expiry | Receipt, reconstruction and post-claim/final physical-call guards compare against current Site time. | Automatic mid-execution interruption when a deadline passes. |
| SIGTERM | Control stops taking new work and gives a live holder bounded shutdown time; unconfirmed outcomes/custody remain. | Proof the holder physically stopped, or an authorization-revocation operation. |

Site-setting matching, TLS server/hostname verification and disabled redirects
remain. Bearer authentication, structural admission and execution delegation
are separate facts. O2 cancellation and O6 generation/restart completion are
later units; no new signature scheme or immediate revocation guarantee is
introduced here. The allocation ownership-unknown limitation remains in
`2026-09-30-resident-allocation-custody.md`.

## Validation

Pinned-toolchain local checks: independent Node vector 1/1; fixed Run materials
package JS/Wasm/native 17/17 each; real native runtime regression 1/1 with SQLite
and a signed bundle fixture (not its environment-guarded no-op path). The real
resident process acceptance and final lint/CI results are recorded in the PR
Validation section at their fixed SHA.

During process-test development, a rejected dispatch left at the stand-in
queue head starved a query. A later test incorrectly waited for observation
ACK after a duplicate Accepted response had resolved its dispatch waiter.
Supplying a query then completed the query but did not ACK the unsolicited
holder report. These are retained test failures, not complete acceptance
passes. The test withdraws only the rejected transport offer; it synchronizes
on actual OS child exit and queries the durable Failed/NoEvidence/
CleanupReleased/no-material/no-quarantine state. Coordinator ACK is separate
from physical cleanup. No product timeout, retry, state or expected start count
is relaxed.

The supplied `pr72-expiry` reproduction at `c0c9301559cb2049e7ea998145dfe6b401115751`
showed three head holders and zero successor entries. The new same-journal
regression asserts one head holder, no head executor call, and exactly one
successor call. An initial test-development failure compared the executor's
occurrence key with the durable attempt identity (different domains); the
assertion now joins actual entry lines to OS-holder claimant identities, not
transport notifications. This does not weaken the zero/one entry expectations.

```sh
node --test scripts/client-values-run-materials-vector.test.mjs
moon test --target js src/run_publication_host --deny-warn
moon test --target wasm src/run_publication_host --deny-warn
moon test --target native src/run_publication_host --deny-warn
ACTQL_TEST_SCRATCH_ROOT=/path/to/task-owned/scratch \
  node scripts/test-native-resident-site.mjs
ACTQL_TEST_SCRATCH_ROOT=/path/to/task-owned/scratch \
  node scripts/test-native-resident-site.mjs --start-authority-only
node scripts/local-checks.mjs run lint
```

Local process acceptance uses an HTTPS Cloud stand-in. Real Cloud/resident Site
integration and Salesforce-org acceptance are not claimed.
