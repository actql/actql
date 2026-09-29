# Salesforce Read→Compute→Effect acceptance

This records the Salesforce acceptance of one Program that acquires records
from the installed Salesforce source, computes locally, previews an update
of the same records, waits for approval across Host restarts, writes, and
publishes its Named Result, through the public Client.

The common path that runs an Effect from an acquisition belongs to the common
Host, Checkpoint and public entries (`feat/source-effect-run`). This PR takes
its fixed SHAs with normal merges. The Salesforce side does not copy or
reimplement common code.

## Current status

Tested source SHA: `4e4e29da0`. It merges the common fixed `c58699ce9`. CI on
this SHA, PR run 36572192554, passed every job.

| Check | Result at `4e4e29da0` |
|---|---|
| `read-compute-effect.acceptance.test.mjs` (Remote HTTP and Embedded) | 17/17 |
| `adapters/connectors/salesforce/test/*.test.mjs` | 227/227 |
| Packed tarballs (`npm run check:local-node-assets`) | Pass, "packed public Client Read→Compute→Effect" included |
| Actual Compute calls: `run-computation-probe.mjs` and `test-acquired-effect-computation-probe.mjs` | Pass; initial 1, recovery 0 |
| Crash stop-points: `test-effect-capture-host-crash.mjs` ×6, `test-effect-capture-crash.mjs` ×3 | Pass |
| Real org, 2026-09-29, instrumented rerun (see "Real org") | Pass: write attempts counted per step, values and cleanup checked |

**What each kind of evidence proves.**
- **Mock request counters** cover every case, including those not run on
  the real org: no write before approval, exactly one write per row, none
  after a restart, none on a refused request.
- **The instrumented real-org rerun** counts every Salesforce request
  attempt at the Node transport, before it is sent, in each step's process:
  - 0 writes before approval;
  - exactly 2 writes on the approved resume;
  - 0 requests on the later restart;
  - 0 writes on the refused request, after its 2 target check reads.

  Each request proposes its own name suffix, so a resend of the first
  request's values would show in the readback. Cleanup must end with a
  count of 0, or the run fails.
- **The refusal cause itself is not observed**, on the real org or the mock:
  the refused Run is identified by its request pattern and `failed`
  status, not by a typed cause (see "Still open").

**Earlier items and their resolution:**

| Item (first seen) | Resolved at | Regression test |
|---|---|---|
| Restart after a partial apply refused the unsent rows (`StalePreview(0, 0)`) | common partial-recovery correction (`docs/reviews/2026-09-29-partial-effect-recovery.md`), in `7d266e73b` | `installed-salesforce-effect.test.mjs` "a restart after a partial apply sends only the unsent rows" and three related cases |
| Recomputation not observable from the public path | `37e4ff5cf` (common Compute probe preload), used from `9dff94330` | `run-computation-probe.mjs` (5 cases), `test-acquired-effect-computation-probe.mjs` |
| One damaged Effect input stopped the whole Host (P2-1) | `508d035e5` (Store startup), then `4449cbc1f` (the refused Run ends) | acceptance "Values-origin: a missing or altered durable Effect input…" and "…Effect input or upstream dependency…" |
| A capture stopped partway could not be recovered or cleaned up (P2-2) | `8434854f2`, `d49d77952`, `181add3f5` | `test-effect-capture-host-crash.mjs`, `test-effect-capture-crash.mjs` |
| Recovered-factory case failed with `SubmissionUnknown` | `0e1942e54` | `effect-run.integration.test.mjs` "two-member … (simulated-installed-recovered-factory)" |
| A definite loss of the written field left the Run `resuming` | `05ab50108` | acceptance "a commit permission revoked after approval writes nothing" (b); "a temporary Catalog outage does not become a definitive commit refusal" |
| A refusal while preparing the Preview was left as execution unknown | `c58699ce9` | `standard-host.integration.test.mjs` (the formerly refused input ends `failed`); acceptance "a checked Preview preparation refusal fails without a commit Checkpoint" |

**Still open:**
- **The typed cause of a target-change refusal is not observable.** The
  public Run status has no `terminal_error` for it, and no diagnostic names
  it. The acceptance tests identify the refusal by its request pattern (the
  target check reads happened, and no write), not by a typed cause. This is
  a request to the common side.

## Historical results (at the time of each SHA)

The sections below record results as they were at the SHA named. They are
kept as evidence; the current state is above.

### At `7d266e73b` (first connection)

**At that time: connected to the common path at `7d266e73b`** (`feat/source-effect-run`,
taken with a normal merge). That SHA is a development dependency. It is not
the final durable-recovery and cleanup SHA: the common side still owns two
P2s from its review.
- **P2-1:** one damaged Effect input stops the whole Host from starting.
- **P2-2:** a capture that stops partway cannot be recovered or cleaned up.

**Salesforce adaptation** (no copy of common code):
- **Source adapter** (`installed-salesforce-source.mjs`): an Effect Run
  prepares and opens its acquisition from the checked Effect owner
  (`preparedEffect`) through the common Effect entries:
  - `clientProgramEffectPrepareQueryAcquisition` and
    `clientProgramEffectPrepareLocalQueryRequirement`;
  - `clientProgramEffectCapturedSourceMatches`;
  - `clientProgramIdentifyCapturedEffectSourceRelation`, which retains the
    dependency bodies for this capture;
  - `clientProgramEffectIssueCapturedSourceLogical`.

  It does not open the computation itself; the common Host does that after
  Run admission. It returns the `requirement` the common plan needs. A
  read-only Run keeps its previous path.
- **Effect factory** (`installed-salesforce-effect.mjs`):
  - Pins up to `maxPinnedResults` (64) Result outputs. That covers the
    upstream Stage Results an acquired Program imports, not only its members.
    Grouping work is bounded to match.
  - Hands the dependency payload owners over to the completed computation
    (`retainPinnedEffectDependencyPayloads`) before the Preview.
  - Binds the Preview to the Stage of the Effect Unit's inputs, where it used
    to pass a fixed 0.
  - The continuation's `unit_id` comes from the common site.

**Results** (mock HTTPS org):
- The acceptance file passes 13 of 15.
- The two failures are the damage cases. Both wait on P2-1: today the Host
  refuses to start, where the tests require the Host to start and only the
  damaged Run to be refused. The tests are not loosened to accept a Host
  start failure.
- The Compute call probe (`run-computation-probe.mjs`, the common preload)
  counts initial Compute 1 and recovery Compute 0 in five cases:
  - the acquired success;
  - the acquired lost reply;
  - acquired halt;
  - the Values-origin partial apply;
  - the Values-origin unknown row.

  It counts the actual shared Compute entry, not notifications.

### At `d49d77952` (merged as `ffa4bfb70`)

These results are recorded apart from the earlier `7d266e73b` results.

| Check | Result at `d49d77952` |
|---|---|
| Acceptance file (Remote HTTP and Embedded) | 13/15. The same 13 pass, Embedded success and stale Preview included. |
| Damage tests (expectations unchanged) | Still fail, at a later point. The P2-1 Host-level part is resolved on the Salesforce path: <ul><li>the Host now starts;</li><li>only the damaged Run is refused on resume, typed (`effect_resume_failed`: `PublicationObjectMissing` / `PublicationObjectCorrupt`);</li><li>0 writes, and no Source re-read.</li></ul> The Run does not end: it stays `resuming`, where the tests expect `failed`. |
| Packed tarballs | Pass, "packed public Client Read→Compute→Effect" included. |
| Compute call probe | 5/5: initial 1, recovery 0. |
| Existing recovery integration (`effect-run.integration`, `installed-salesforce-effect`, `installed-salesforce-effect.host`) | 68/69. The failure is the recovered-factory case, `SubmissionUnknown`, as at `7d266e73b`. |

Tracked separately:
1. **A refused damaged Run is not ended.** It stays `resuming`; this is the remainder of P2-1.
2. **Handoff of an interrupted partial capture (P2-2).** The common side is working on it.
3. **A written field lost under the same configuration stays `resuming`.**
4. **The recovered-factory case fails with `SubmissionUnknown`.**
5. **A refusal while preparing the Preview is left as execution unknown.**

## The Program and independent expectations

- **Acquire:** read `Test_Record__c` through the records view (scan, filter
  `Name <> 'record-2'`, select `Id`, `External_Key__c`).
- **Compute:** derive `next_name = concat(External_Key__c, '-processed')`
  and select `Id`, `next_name`.
- **Effect:** update `Name` of the same records by `Id` (halt by default;
  `continue` in the independent-rows case).

Expected values are written by hand in `read-compute-effect.fixture.mjs`:
- **Targets:** records 1 and 3; record 2 is filtered out and never written.
- **Bodies:** `{"Name":"key-1-processed"}` and `{"Name":"key-3-processed"}`.
- **Named Result `updates`:** the two rows above.
- **The org afterwards:** the two targets renamed, record 2 unchanged.

## Cases

| Case | Entry | Expected |
|---|---|---|
| Success: acquire, filter/derive, Preview, held, restart, approve, restart and resume, 2 writes, Named Result, restart with no further write | Remote HTTP, Embedded, tarball | Exactly the two bodies, once each. No Source re-acquisition after the restart. Named Result and final org state as above. |
| Target changed after acquisition, before Preview | Remote HTTP | The Preview observes the target as it then is. The existing guard compares at send, so the Set is written. |
| Target changed after Preview, before send | Remote HTTP, Embedded, tarball | Refused before any write (stale Preview); the Run fails. A race after the pre-send check is not claimed to write nothing. |
| Approval expired | Remote HTTP | No write. Expiry uses the Host's `checkpointTtlMs` with a bounded wait past `expiresAt`, as the read approval test does. |
| Commit permission revoked after approval (a): the account configuration now denies | Remote HTTP | No write. This checks refusal on a configuration change only. |
| Commit permission revoked after approval (b): same installation and configuration, the org no longer lets the user update `Name` | Remote HTTP | No write and no Source re-read; the Site's current-use recheck refuses the resume. Under the existing contract, a provider observation failure before the checked preflight stays retryable, so the Run is not ended (it stays `resuming`, as a Values-origin Run does today). Whether a definite loss of the field should end the Run is a question for the common side. |
| Reply lost after the org applied the second write | Remote HTTP | That row stays unknown and is never resent. The Run is `needs_reconciliation`. The org shows both rows applied, and a restart sends nothing. |
| Source read denied, or deferred (delegated), after publication | Remote HTTP | Refused before any provider request: no describe, query, target read or write, and no Checkpoint. Read deferral is not supported on this path. |
| Failure before the capture completes (every source query answered 503) | Remote HTTP | The Run fails with no answerable Checkpoint and no write. A restart neither re-acquires nor writes. |
| Durable Effect input body, or the upstream dependency body, missing or altered while stopped, after approval | Remote HTTP | The Host starts; only that Run is refused before any write; the Source is not queried again to refill it; the org is unchanged. The target is chosen by role from the Store's own holding manifests: the Effect input is the `effect-source` holding's object, and the upstream dependency is the object only the `effect-capture` holding names (the acquired Stage's Result). Fails today on the common P2-1: the Host refuses to start. |
| Values-origin: the Effect input body damaged the same way | Remote HTTP | Same expectation; fails today on P2-1. |
| Halt: serial rows, the second of three rejected definitively | Remote HTTP | Applied, then failed, and the third never sent. The Run fails. Each row's outcome is kept, and a restart sends no row again. |
| Continue: serial rows, the second of three rejected definitively | Remote HTTP | Applied, failed, then applied: each row sent once. The Run fails. Each row's outcome is kept, and a restart sends no row again. |

## Findings for the Salesforce side

- **Effect factory input.** (Before the connection; at `7d266e73b` the
  common Host opens the acquired computation for this call.)
  - The factory takes its rows only from `facts.openComputation()`, which the
    Host then wired to the source-free computation
    (`installed-effect-site.mjs:208`, `embedded-local.mjs:634-642`).
  - The factory stays as it is: it should consume what `openComputation()`
    returns for an acquisition-based Run.
  - Ownership, closing and the restore contract of that computation are
    questions for the common side.
- **Collections.**
  - The installed Effect never takes the sObject Collections route:
    `issueSalesforceEffectCapability` is called without `collection`, which
    defaults to serial rows.
  - So `continue` sends single-record writes one by one. Each row is still
    settled independently.
  - Collections partial results stay covered by the provider tests
    (`effect-run.integration`). They are **not** verified through the public
    Read→Compute→Effect path. Wiring Collections into the installed Effect
    is a separate task.
- **Source capture.**
  - It lives only in its process and is closed after compute
    (`client-dispatch-owner.mjs`).
  - An Effect after a restart must write from the computed result made
    durable before approval, never re-acquired. The acceptance tests count
    Source queries apart from target check reads.

## Conditions shared with the common side

The common side's contract difference (PR #53 comment, "upstream dependency
inventory") matches these conditions:
- the checked owner selects the dependency closure;
- the bodies, Captured Run and Preview are durable before the approval wait
  is published;
- limits are checked at issuance and recovery;
- a missing, duplicate, mismatched or cyclic dependency is refused, never
  refilled;
- cleanup owners and unknown-write evidence are kept.

**Historical (resolved; see Current status): an observable for recomputation.** Source
re-acquisition is counted through Source queries. A recomputation from the
retained input, however, produces the same output and no provider request.
D cannot see it from the public path, so D asks for a Host diagnostic (for
example through the existing `observe` hook) that a test can count. If such
notifications can be dropped, zero notifications is not proof of zero
recomputations; the observable must be one whose absence is meaningful (for
example a durable per-Run computation count).

**Historical (resolved; see Current status): a damaged Effect input stopped the whole Host.** This was the common side's
P2-1. A missing or altered Effect input or dependency body makes the Host
refuse to start (`InstalledHostInitializationFailed`), rather than failing
only that Run. Nothing is sent. D's damage tests require the Host to start
and only the damaged Run to be refused.

**Historical (resolved; see Current status): an existing recovered-factory
case failed at `7d266e73b`.** In `effect-run.integration.test.mjs`, "two-member captured
Effect Run publishes after all rows settle (simulated-installed-recovered-factory)"
fails with `SubmissionUnknown`. It fails the same way:
- on a clean build of `7d266e73b` alone;
- on the merged branch with D's factory changes reverted.

So it is not a Salesforce-side change. The other eight variants of that
case pass.

**Historical (resolved; see Current status): a definite loss of a written
field.**
When the org reports the target field is no longer updateable (same
installation and configuration), the Salesforce recheck refuses the resume
before the checked preflight. The common owner treats that as a retryable
provider observation failure, so the Run stays `resuming` rather than ending.

- After a restart:
  - no Source re-acquisition or recomputation;
  - the write input is the durable input bound to the approved set, never
    rebuilt from the Preview display alone;
  - a missing, corrupt or mismatched durable input is refused before sending.
- The durability point, its ownership and recovery are the common side's.

## Real org

Run on 2026-09-29 on the approved Dev org. It went through Embedded Local,
with each step in its own process so each step was a Host restart. The
object and fields were the dedicated `ActQL_Test_Record__c`, `Name` and
`External_Key__c` only; no schema or permission change.

Each run created three rows, each tagged with that run's key prefix and its
Id recorded. The Program's filter selected only two of them by key; the
third was the run's own row the filter drops.

### Instrumented rerun (current evidence)

Salesforce SHA `00f1b48db`; its code is the same as `4e4e29da0` (common
`c58699ce9`). A preload in every step's process counted each request
attempt at the transport before sending. It recorded only the step, the
method and a coarse category; no path, Id, body, header or token.

| Step | Status or readback | Salesforce request attempts |
|---|---|---|
| Publish source; publish Effect | Published (one SourceView, one update Mapping) | 1 describe each; no write |
| Submit request 1: acquire, filter, derive, Preview | Held for approval (`waiting_checkpoint`) | 4 describes, 1 query, 4 record reads; no write |
| Readback before approval | All three rows unchanged | — |
| Restart, approve | `committed` | none |
| Restart, resume | `succeeded`; Named Result exactly the two `-processed-1` names | 1 describe, 2 record reads, **2 writes** |
| Restart again | Still `succeeded` | **none** |
| Readback | The two targets carry the `-processed-1` names; the filtered-out row unchanged | — |
| Submit request 2 (suffix `-processed-2`) | Held for approval | 4 describes, 1 query, 4 record reads; no write |
| One target changed outside ActQL; restart, approve | `committed` | none |
| Restart, resume | `failed` | 1 describe, 2 record reads, **0 writes** |
| Readback | Only the outside change; no `-processed-2` value anywhere | — |
| Cleanup | The three rows deleted by Id; count 0 | — |

The checks that decide the result (`liveProblems`) found no problem. The
recorder itself is tested without org access. These cases must fail it:
- a same-value write on the restart;
- a failure before the target check reads;
- a write on the refused request;
- a write before approval, or a missing write.

A delete failure, rows left, or a count that cannot be read makes the run
exit non-zero, after the evidence is saved.

The refusal cause is not observed: the second Run is `failed` after its
target check reads, with no write. No public status or diagnostic names the
target change as the cause.

API use: 43 calls by the org's daily counter (before and after). The
internal ledger counted 51 by estimate.

### First run (at that time, `4e4e29da0`, not instrumented)

It showed statuses and values only:
- after restarts, `succeeded` with the expected Result and org values;
- after the target changed, `failed`, with the outside change kept;
- cleanup count 0.

It did not count write attempts, and its second request proposed the same
names as the first. API use: 30 calls by the org's counter.

### Not run on the real org

Mock only:
- unknown result after a lost reply;
- partial success (halt and continue);
- approval expiry;
- revoked commit permission;
- damaged durable inputs;
- a stop partway through saving.

## Tests

- `adapters/connectors/salesforce/test/read-compute-effect.acceptance.test.mjs`:
  every case on Remote HTTP, and the Embedded success and stale-Preview cases
  (each Embedded step in its own process, so each is a restart). It runs in
  `npm run check:salesforce-site`.
- `scripts/test-packed-salesforce-source.mjs`: the success and stale-Preview
  cases from the installed tarballs, with no checkout or MoonBit.
- `salesforce-effect-site.fixture.mjs` gains a stateful org, off by default:
  - applied writes change the records;
  - a missing target is 404;
  - replies can be lost after the update was applied;
  - per-row Collections application and replies;
  - a query hook;
  - direct record changes.
