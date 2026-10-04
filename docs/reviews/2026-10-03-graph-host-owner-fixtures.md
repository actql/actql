# Graph Host owner fixture reuse

Baseline: `b18632b65570713e36c0a83e8afd0063bc37a5c3` (`origin/main` when this worktree was created).
Branch: `test/graph-host-owner-fixtures`.

## Scope and reuse

The two added cases use the existing keyed Graph Host fixture for MATCH nodes
and MATCH edges. Existing normal cases, all nine variants at quantum 1, 7 and
1024, and the existing cancellation case remain. The new cases enumerate those
three quantum values. The original counterexample stopped at quantum 1;
the fixed-source JS runs below complete quantum 1, 7 and 1024 in each case. No workflow, history validator, product source,
target selection or execution frequency was removed or changed.

The existing `delayed_cleanup_provider` fixture now forwards the original typed
Relation/Carrier inputs. Its old default remains one false response followed
by real cleanup. The two Graph cases request false, then error, then real cleanup
for the exact BoundPrepared owner and original MATCH occurrence. Unrelated
construction must have made zero injected cleanup calls. This is a test callback
wrapper around real execution, not a second owner or a synthetic accounting ledger.

Two small functions share consumer close checks and disposed-execution cleanup
retry checks. They observe the real CapturedDAG ledger and actual completed
output storage bytes. Each consumer close returns exactly that output's holding;
a repeated close must leave the entire intermediate ledger observation unchanged.
Cleanup false and error preserve the reservation and holding. The normal cases
retain their existing closure order. In the MATCH pilots the second consumer
is still executing when the first consumer and producer public port close.
Its acquired input remains available and the real holding stays charged; its
independent expected rows and finalization pass. A's separate #272 fix makes
completion succeed against the admitted input binding, without reopening the
public port. The fixed-source runs below reach last-consumer retention, exact
cascade credit, final cleanup retry and unchanged-ledger repeated close. The
original #270 reproduction without A's fix remains red.

Reservation release requires execution disposal in the current Host contract.
A live output's provider cleanup callback completing alone is not evidence that
the Host reservation has been released. The tests follow that actual boundary.

## Operation-specific obligations

Exact MATCH rows, consumer projections and row order stay outside the owner
functions. Node rows compare the complete typed element identity. The expected
definition domain is hashed from a literal canonical preimage of the constructor,
two ordered VALUES producer occurrences and declared field projections. It is
not obtained from the checker, runtime Graph, or observed output. Edge rows and
consumer rows use independent literal numeric/string expectations.

Provider material/view lifetime, snapshot generation, separate Graph identity/type
and resource boundary tests remain untouched. This work does not establish new
whole-program schema guarantees, physical heap bounds or GC reclamation.

A future Graph operation using this same Host boundary can reuse the real task
runner, scoped cleanup wrapper, exact consumer-credit/idempotence checks, and
cleanup reservation checks. Its checked occurrence, independent rows/projections,
identity/type conditions and operation-specific boundaries still require review.
Different material/view or execution boundaries require their own correspondence.
No test deletion, CI speedup or formal implementation proof is claimed.
The three specific JS mutation observations below are not general mutation
equivalence or other-target detection guarantees.

## Focused verification

The checked-in ActQL local verification skill was followed. Both selected runs
used `scripts/local-checks.mjs`, a 120-second budget, and the JS backend:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/property_graph_host_custody_wbtest.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/local_time_series_wbtest.mbt --filter 'standard Host runs time series with two retained consumers'
```

Final results: Graph Host 4/4, existing TimeSeries default-wrapper case 1/1.
`git diff --check` and file-scoped `moon fmt --check` passed. Toolchain:
MoonBit `0.10.12+1634b282e`, moon `0.1.20260904`; borrowed installation at
`/Users/t14i/workspace/20260822/actql/.toolchains/moonbit-0.10.12+1634b282e`.
`node_modules` is a symlink to `/Users/t14i/workspace/20260822/actql/node_modules`.
Both borrowed dependencies must be preserved.

Retained final successful evidence under this worktree:

- `_build/focused-evidence/focused-test-HVQKjY` and `_build/local-checks/attempts/run-yhg2zZ`.
- `_build/focused-evidence/focused-test-NlNa5u` and `_build/local-checks/attempts/run-VbChLi`.

Earlier unsuccessful attempts also remain separate. The first sandbox invocation
could not inspect the wrapper's owned process group; no test success is claimed
for that invocation. Narrow reruns followed concrete test-fixture corrections.

## Main integration and focused acceptance

The pre-integration results above belong to `afa3e2ac1a8ae5f35c64046cc59088add5050ffe`.
After #242 and #246 reached main, this branch normally merged
`11fde3441fdcf0766c583c5173ccf8e788a09751` with no conflicts. Existing product
owners, CI cost controls, declarations, supplements and introduction history
were retained. No alternate JSON composition path or compatibility fallback
was added.

The first light history check rejected the actual #246 main merge because its
workflow resolution declaration was missing. The added
`main-json-composition-246-resolution.json` binds that merge's two ordered
parents, its single merge base, workflow blob digests and modes, and 34 inherited
declaration dependencies. It changes no workflow bytes or validator rules.
The same source-bound declaration is preserved on the recovery branch's
post-merge snapshot `bf4b509d776bbb4e643374f59b17181574537e2a`. It was not part
of the merged #267 head; it reached main with the #270/#272 integration.

At `7d26f502bedbf7773d85aabfc562bb990a330149`, the existing Git-only history
validator passed and the bounded JS Graph Host selection passed 4/4. Its new
evidence is `_build/focused-evidence/focused-test-IS1mMx` and
`_build/local-checks/attempts/run-8GOM7e`. No broad local campaign or old CI rerun
was added for integration. This documentation update changes none of those
tested source bytes. Fresh submitted-head PR CI is recorded in the PR.

During this work #267 also normally merged into main at
`b36d7864b57dc654cc03f583d8391e9ba2a506b3`. This branch normally merged that
new main as `7d998820bb9375dc7717f9a6df0ae17e169d8c71`, without conflicts.
The recovered provider-construction evidence is now inherited from main;
this branch has no unmerged dependency. The Git-only history validator passed
again. Both edited test files remain byte-identical to the focused JS run above,
so no further test or build was added for this second integration.

## Fixed-source normal and mutation acceptance

A's product fix is #272 at
`d5c1e949cec0064a8898554a6bf87f4e59fff235`, whose parent is the exact G
counterexample `7f5c7c8353c8058c5710a6cd29f7ba3af3b53215`.
An isolated detached worktree, `worktrees/actql-graph-host-owner-mutations`,
ran only the two selected MATCH cases on JS with the pinned toolchain and
120-second bounded/nonzero wrapper. It borrows `node_modules` and the toolchain
listed above; its incremental `_build` is private. No product mutation or fix
was added to G's production branch.

The clean fixed-source baseline passed **2/2**, completing quantum 1, 7 and 1024
inside each case. Each of the three separate mutations then failed both cases
at its intended intermediate assertion, exit 2. Each was restored to the exact
Git bytes and mode `100644`, and the same selected cases passed **2/2** in a
fresh process. Compiler errors, timeout, the original completion refusal and
final-zero-only checks were not used as detection evidence.

| Invocation | Focused evidence directory | Local-check attempt | Result |
| --- | --- | --- | --- |
| Clean #272 baseline | `focused-test-BYUZlJ` | `run-EleUn5` | 2/2 pass |
| Early scratch credit | `focused-test-YmqZvT` | `run-uYpxEo` | 0/2 pass; line 210, pending execution reservation must remain positive after MATCH cleanup false, with cleanup counter already 1 |
| Restored scratch source | `focused-test-SeeV92` | `run-7AFStk` | 2/2 pass |
| Double holding credit | `focused-test-JfdDBE` | `run-HAEhuJ` | 0/2 pass; exact consumer-close credit assertion, lines 552–556 |
| Restored ledger source | `focused-test-VR0TKk` | `run-X66vzi` | 2/2 pass |
| Missing child dependency | `focused-test-qTahjC` | `run-qYalMD` | 0/2 pass; last-consumer holding after producer-owner cleanup, lines 428–433 |
| Restored retention source | `focused-test-v9G3Yz` | `run-AZ35Uw` | 2/2 pass |

Evidence paths are relative to the isolated worktree:
`_build/focused-evidence/<directory>` and
`_build/local-checks/attempts/<attempt>`. Preserve all seven invocations.
`_build/graph-owner-mutations/{early-scratch,double-credit,lost-consumer}`
retains each exact patch and source record with fixed SHA, before/after SHA-256,
mode, result references and checked restoration. These records describe finite
runs; they are not capacity certificates or automatic evidence-gate claims.

The scratch mutation makes the pending reservation zero while real cleanup is
false. The double-credit mutation removes twice the exact holding quantity, so
the first consumer's ledger delta disagrees with its real output storage bytes
while other holdings remain. The child-dependency mutation removes the closed
producer's holding after its own cleanup; this is observed before the remaining
consumer closes. Tests still require that consumer to retain the holding and
that its later close return its own plus the parent holding exactly once.

These are JS mutation observations. The selected fixed-source tests and existing
normal/cancellation tests remain required on all CI targets; JS mutation kills
are not Wasm/native mutation evidence. No existing test was removed and no CI
speedup or whole-implementation proof is claimed.

## Fixed-source CI correspondence

A's automatic PR run [37131655117](https://github.com/actql/actql/actions/runs/37131655117)
uses the same fixed SHA `d5c1e949cec0064a8898554a6bf87f4e59fff235`.
The three Core job logs show unfiltered `moon test --target <target> --deny-warn`
execution, including the unchanged Host whitebox test file (no target-specific
exclusion on these cases). The recorded totals are:

| CI target | Job | Executed / passed / failed |
| --- | --- | --- |
| JS | `111228243235` | 7413 / 7413 / 0 |
| Wasm | `111228243276` | 7409 / 7409 / 0 |
| Native | `111228243301` | 7496 / 7496 / 0 |

These are finite normal-implementation CI results at A's fixed source. They
include the existing normal/cancellation tests and do not repeat the three
Host mutations on Wasm/native. The locally isolated mutation results above
remain JS-only. The same automatic run subsequently completed with conclusion `success`,
including its final evidence publication/aggregation. Any later submitted-head CI must still be checked independently; this
successful run does not establish a different HEAD's result.

## Completed main integration

#272 reached main as `7081dedfd69f5794de11076ab27249c4f57b0c66` on
2026-10-04 JST; #270 is also recorded as merged. The integration preserves
G's tests and original #246 declaration alongside A's acquired-input fix.
G normally merged this main revision without conflicts as
`cc9d2bfd96abb656963207f11dc84e88a9dfd8f3`.

The two test files, three product-fix files and original #246 declaration
have no residual diff against main. The five test/product files also match
the successful fixed-source revision recorded above. The original counterexample
and three mutations remain evidence of their actual fixed SHA; no new mutation
campaign or broad test was run merely to confirm integration.

The first documentation PR run exposed a missing declaration for G's actual
normal merge `cc9d2bfd96abb656963207f11dc84e88a9dfd8f3`.
`resolve-host-owner-main-7081dedfd.json` adds that distinct merge's provenance:
two ordered parents, both maximal common ancestors, the required union
0 + 13 = 13 paths, exact before/after blob digests and modes, and 50 inherited
declaration IDs. Existing records are preserved; the validator and workflow
are unchanged. The Git-only history entrypoint passed after this addition.
This necessary metadata is separate from the two residual review documents.

Main then advanced to `ba3d6d128` (#266) and was normally merged without
conflicts. Subsequent documentation and test changes require their own
automatic PR CI; earlier runs do not certify a new HEAD.

## Executed mutation sites and detection scope

Recipes were first reviewed against `7f5c7c8353c8058c5710a6cd29f7ba3af3b53215`
and their exact source/preconditions rechecked at A's fixed revision above.
The following changes were injected one at a time **only in the isolated
worktree**, detected and restored. A changed future site requires review, not
a silent pin update or another equivalent-looking mutation.

| Fault | Actual product mutation site | Required intermediate failure |
| --- | --- | --- |
| Unreclaimed scratch credited early | `src/physical_strategy/task_execution.mbt`, `task_output_remaining_scratch`: change only the unreleased `execution.scratch` branch to `0L`. Keep the cleanup witness call and successful output path. | After the actual MATCH callback returns false, `pending.reserved_execution_bytes > 0L` must fail. The MATCH counter must already be 1. A completion/allocation refusal before this assertion does not qualify. |
| Same holding credited twice | `src/physical_resources/ledger.mbt`, `release_allocation`: subtract `2L * holding.bytes` instead of `holding.bytes`, leaving owner/live checks and resource removal intact. This specifically tests double credit of one exact token; it does not prove all invalid-token rejection behavior. | `close_graph_host_consumer` must fail at `consumer close must return each owned holding exactly once`: the ledger delta must equal the actual output's storage bytes, plus the exact closed-parent bytes only on the final consumer. The first consumer must have a nonzero holding; final balance zero is not the criterion. |
| Closed producer loses its remaining consumer dependency | `src/physical_strategy/retention.mbt`, `collect_captured_retention`: remove only the `child.parents.contains(task)` retention guard. Preserve the active-edge guard, pins, owner cleanup checks and release callback. | After consumer completion and producer-owner cleanup succeeds, `last consumer must retain the producer holding after owner cleanup` must fail. At this point the producer public port is closed and its execution cleanup no longer masks a missing child dependency. The observed holding must remain until consumer 6 closes. Failure at the known Host completion refusal does not qualify. |

The active-consumer observation and completed-consumer dependency are separate.
The in-flight assertion alone cannot establish detection of a removed child
guard: the active-edge guard and producer cleanup may independently keep the
holding. Conversely, the later child-guard mutation does not establish removal
of the active-edge guard. Record the phase actually observed.

## Reuse guide for A/B/C/D

The fixed-source normal and mutation/restoration runs above establish this
finite JS example, now integrated into main. Reuse its declared scope; record
new checks and submitted-head CI separately for any adoption change.

| Reuse at the same Host boundary | Add or retain for each operation | Confirm on the real connection |
| --- | --- | --- |
| Exact token credit on consumer close and unchanged ledger on repeated close | Independent expected rows, authored projection order, schema/type conditions and operation identity. Do not derive these from runtime output or owner helpers. | The installed registry selects the intended provider, owner and checked occurrence with the actual typed inputs. Equal CIDs or scope labels do not establish this. |
| Scratch responsibility across cleanup false/error/retry and preserved consumed work/transfer | Algorithm-specific work and capacity limits, one-short cases, NULL/empty/tie behavior, unique fault regressions and backend/Store tests | The callback failure hits that execution, not construction or another child. Observe the real run ledger and output storage quantities, not a second accounting table. |
| Closed public port, live acquired input, consumer progress, last-consumer retention and exact-once cascade return | Each operation's own output meaning and input ownership conditions; preserve separate material/view lifetime and actual Store/process obligations | Public-slot revocation and acquired-input release are distinct. Confirm failed new public lookup, acquired-input validity and consumer completion against its existing ownership evidence. |

The common Session/chain model theorems retain their declared scopes and
assumptions. They do not by themselves certify Host fan-out, these Graph
identities, arbitrary provider stop behavior, runtime bytes or physical GC.
These Host assertions and executed JS mutations are finite implementation evidence;
no whole-implementation formal proof is claimed.

When adding an operation, reuse an existing owner action/check only after its
preconditions match. Review the new independent values, input/output connection
and residual boundaries. Keep an old assertion if it is also the only witness
of correct transported data. Count reduced repeated authoring/review obligations,
not generated cases, helpers moved between files or unchanged runtime duration.

## Applying the example during operation development

Use this method when an operation goes through the same captured Host task,
installed managed dispatch, completed output and real reservation/holding ledger.
A carrier name, identical result CID or use of the same Session is not sufficient
connection evidence. Keep material/view, Store, process and backend obligations
in their existing tests.

1. Identify the checked producer/consumer task positions, original prepared
   occurrence and installed provider. Keep typed acquired inputs attached to
   the real task runner. Write the operation's independent expected rows,
   projection/type/identity conditions and residual boundaries before reusing
   an owner check.
2. Reuse the scoped `delayed_cleanup_provider` only if its callback sequence
   matches the scenario. The Graph example injects false/error/retry into MATCH
   alone; the TimeSeries default is false/retry. Check construction/unrelated
   tasks did not receive the injection. Do not introduce operation switches into
   a universal lifecycle harness.
3. Reuse `close_retained_host_consumer` where the closing consumer has its own
   real charged output holding. Keep sibling availability and correct-data
   assertions outside it. Its optional parent credit is valid only after the
   public producer port is already closed and this is the last retaining child;
   obtain that quantity from the exact real parent output. Shared backing,
   views or a different ownership boundary need their own correspondence rather
   than multiplying storage bytes by references.
4. To verify retention after producer close, start the remaining consumer before
   it has output, close the public port, and preserve its acquired material.
   Check failed new public lookup, unchanged holding, independently expected
   execution values and completion. Only after producer-owner cleanup no longer
   masks a missing dependency can the remaining-child assertion establish the
   dependency. Rereading an already materialized result alone cannot do so.
5. Run the smallest affected JS selection with the repository bounded/nonzero
   wrapper. Review the test counts and the exact source revision. A new scenario
   must pass before a mutation is counted. For a changed ownership path, select
   its real mutation site, require the intended intermediate assertion, restore
   exact bytes/mode, and rerun. Existing unchanged evidence can be referenced
   with its actual scope; it is not a new mutation run on the current SHA.
6. In the PR, list reused actions/invariants, added operation expectations and
   connection checks, residual tests, selected results, and exact submitted-head
   automatic CI. Distinguish model theorems, finite implementation checks and
   JS-only mutation observations. Count authoring/review obligations actually
   reused, not case count, code motion or alleged CI time savings.

For the Graph example the minimal local selection is:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/property_graph_host_custody_wbtest.mbt --filter 'Host MATCH *'
```

Use the repository's pinned toolchain environment. See
[local verification](../development.md#local-verification) for command selection
and [focused execution](../development.md#focused-test-execution) for the nonzero
count/evidence contract. Do not run a full campaign merely to adopt this example.

## TimeSeries reuse of the same Host close invariant

`standard Host runs time series with two retained consumers` in
`src/query_integration/local_time_series_wbtest.mbt` now calls the same close
check as MATCH. The helper was renamed from `close_graph_host_consumer` to
`close_retained_host_consumer`; its body and the Graph callback sequence are
unchanged. No new harness, algorithm, owner, fixture or operation switch was
introduced.

The TimeSeries path already uses the installed managed dispatch, retained
Relation inputs, admitted completion, real CapturedDAG ledger and actual output
storage bytes. Both consumer outputs have their own charged holding. Its
producer port stays open during consumer close, so parent cascade credit is
zero; the last-consumer-after-producer-close scenario remains the Graph-specific
connection evidence above and is not claimed for this TimeSeries change.

| Obligation | Reused or retained |
| --- | --- |
| Close each consumer through its Host and dispatch operations | Two handwritten close blocks (nine lines) become two calls to the existing helper. |
| Return the exact owned output holding | Shared assertion compares the actual ledger delta with the completed output's storage bytes at each close. |
| Repeated close does not credit again | Shared check compares the entire intermediate ledger observation after a second close/cleanup refresh, with other holdings still present. |
| Closing the first consumer leaves sibling and producer available | Existing TimeSeries assertions remain immediately after the shared call. They are availability checks, not proof of in-flight input retention. |
| TimeSeries meaning and publication | The three independently authored 1969/1970 timestamp rows, both consumer row checks, literal NamedResult CID and BeforePublication deadline checks remain unchanged. |
| Provider cleanup and final recovery | The existing TimeSeries false/retry callback sequence, counter 1 before consumption / 2 after disposal, and final reservation/holding-zero checks remain. The Graph false/error/retry helper is not used. |

Adding another consumer at this same owning-output boundary now requires its
connection and independent expected data plus a helper call; authors do not
rewrite the close order, ledger-delta calculation or repeated-close invariant.
This is an actual second caller, not a moved fixture or a count of generated
cases. Other material/view, capacity, time/overflow, cancellation and backend
obligations remain in their existing tests. No existing test was deleted and
no CI time reduction is claimed.

### Focused adoption checks

The bounded/nonzero JS wrapper executed:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/local_time_series_wbtest.mbt --filter 'standard Host runs time series with two retained consumers'
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/property_graph_host_custody_wbtest.mbt
```

Results: TimeSeries **1/1**, Graph **4/4**. Their exact test bytes are in
`d087d67e1` (the test-only commit); helper implementation bytes are unchanged
apart from its name. The selected checks ran before that commit, with the
source changes present; this is not a claim that a clean later HEAD was tested.
`moon fmt --check` on those two files and `git diff --check` passed.

Retain local evidence under `worktrees/actql-graph-host-owner-fixtures`:

- TimeSeries: `_build/focused-evidence/focused-test-4iBiIh` and
  `_build/local-checks/attempts/run-GrbHTm`.
- Graph: `_build/focused-evidence/focused-test-9qY2sX` and
  `_build/local-checks/attempts/run-Lhyk4w`.

The later normal main/documentation merges changed neither test file. The
submitted HEAD's automatic PR CI is recorded separately in the PR. No broad
local Core, all-target, proof, packed or performance campaign was added.
The fixed `d5c1e949...` Graph mutations retain that source's scope; no new
TimeSeries mutation execution or other-target mutation detection is claimed.

## Limited deduplication of existing Relation Host cases

The adoption baseline is main `b5d5261eff36409e247d8e866edee048fd8c9f2e`
(including #274 and #276). The selected
group is the literal and parameter lag cases in `local_managed_lag_wbtest.mbt`
and `standard Host runs bounded as-of join for two consumers` in
`local_managed_asof_join_wbtest.mbt`. The mapping below was made before replacing
their close blocks. The analytic/unary multi-variant fixtures are outside this
small group.

| Existing observation | Shared check or retained obligation | Actual connection |
| --- | --- | --- |
| Two consumer close sequences per fixture, including first-output unavailability | Use `close_retained_host_consumer` for both consumers; exact real holding credit and unchanged intermediate ledger on repeated close are checked once in its implementation. | Lag tasks 4/5 consume task 3; as-of tasks 4/5 consume task 3. Each real completed consumer output and its own installed dispatch operations are passed to the helper. |
| First close leaves the sibling and producer available | Keep both assertions immediately after the first helper call. | Producer public ports remain open. No parent cascade credit is requested. These observations must not be relabeled as in-flight input retention evidence. |
| Lag semantics and projection | Keep literal expected rows, NULL/partition/ordering/offset behavior, the reordered consumer projection, and the literal/parameter registrations. | VALUES task 1 passes its actual output to uniqueness task 2, then lag task 3; provider-required quantum-1 execution and the advance-count assertion remain. Each consumer receives the actual producer output and rows. |
| As-of meaning and identity | Keep the expected chosen value 300, reordered consumer projection, search metadata and independent NamedResult CID/status. | Two actual VALUES outputs and their rows enter the installed as-of provider at task 3 with managed obligations; both consumers obtain that output through the existing Host runner. |
| Producer/input close, cancellation, provider lifetime and capacity | Retain all existing producer/source close operations, intermediate connection observations, final recovery assertions and separate cancellation/provider tests. | The as-of two-input boundary is unchanged; the consumer-close helper does not certify that join's input ownership or algorithm bounds. |

Four authored close blocks shared by these three cases are replaced, rather
than moving a fixture or removing semantic assertions. For another consumer
at this same boundary, authors supply its actual operations/output and
independent expected data; they no longer repeat close sequencing, the exact
credit calculation or idempotence assertions. The lag helper still serves its
two existing variants; no new operation switch, harness or product code is
introduced. No test case, target or execution frequency is removed. Repeated
close adds an observation, so no CI speedup is claimed.

### Mutation applicability and remaining connection evidence

The existing fixed-source Graph double-credit mutation targets the same
`release_allocation` implementation and exact-credit helper assertion used by
these consumers. `ledger.mbt`, `retention.mbt` and `task_execution.mbt` are
byte-identical between `d5c1e949cec0064a8898554a6bf87f4e59fff235` and this adoption
baseline; the close helper's body also remains unchanged. This supports reuse
of the previously demonstrated invariant and its failure mechanism. It is not
a newly executed mutation on these Relation cases or the submitted HEAD.

Early scratch release and missing child-dependency detection remain established
by the unchanged MATCH false/error/retry and producer-close scenarios, with
their precise intermediate assertions above. The migrated cases keep the
producer open and do not inject pending cleanup. Their materialized sibling
availability cannot establish either detection. A claim about pending cleanup
or retention after producer close on these particular connections would need
its own unmasked scenario and targeted mutation confirmation. No such claim
or substitution is made: those Graph tests, the TimeSeries cleanup checks and
all operation-specific boundaries remain required. The shared ledger delta
and repeated-close checks strengthen these consumers without replacing those
distinct observations with final resource zero.

### Focused deduplication acceptance

The following bounded/nonzero JS selections passed with the changed test bytes
that were subsequently committed as
`261fc4f9580068c60c4f0821e944107076d3c5f9`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/local_managed_lag_wbtest.mbt --filter 'Local managed * lag feeds two downstream Computes'
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js src/query_integration/local_managed_asof_join_wbtest.mbt --filter 'standard Host runs bounded as-of join for two consumers'
```

Results: lag **2/2**, as-of **1/1**. File-scoped `moon fmt --check` and
`git diff --check` passed. The two unsupported sandbox process-group inspection
attempts are not test successes; the same selected commands were rerun with
permission for the bounded wrapper's inspection. Preserve this worktree's
evidence:

- Lag: `_build/focused-evidence/focused-test-r3Wz2w` and
  `_build/local-checks/attempts/run-5L3Dkm`.
- As-of: `_build/focused-evidence/focused-test-HdLFXC` and
  `_build/local-checks/attempts/run-FcNc8E`.

The test diff removes 18 lines and adds four helper calls (net 14 fewer test
lines). It keeps all three cases, independent expectations and connection
observations. This records reduced repeated close authoring/review, not a
reduction in executed semantic coverage or CI duration. No new mutation,
all-target, Core-wide, proof or packed local campaign was run. The submitted
HEAD's automatic PR CI is recorded separately in the PR; the earlier Graph
and TimeSeries runs do not certify this HEAD.
