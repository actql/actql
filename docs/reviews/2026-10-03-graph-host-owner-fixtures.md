# Graph Host owner fixture reuse: integration status

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
No test deletion, CI speedup, formal implementation proof or mutation equivalence
is claimed by this change.

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
of the merged #267 head; #270 carries the common history fix for review.

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

## Main integration still required

G normally merged main `336636c0bf6c5065d14941c7008c43b9897c7f4b` (#268)
as `129ab2bd90944af2b7dab14e9007b14231aab2d9`, without conflicts.
The new four-producer CI configuration and all original declarations were
preserved. The Git-only history validator passed; no full local campaign was
added. This main merge changes neither the two test files nor the three product
files changed by A. G's branch intentionally does not contain A's fix yet.

#272 was originally stacked on #270 and has since been retargeted to main
at the unchanged fixed SHA. Its main-relative diff therefore includes the
published G test changes, both review records and the existing #246 declaration,
as well as A's three product files. This is not a product-files-only diff; the
PR scope and review must account for those inherited changes. No PR was merged
into a dependency branch. G must adopt the final integrated main revision
before claiming acceptance of #270's submitted HEAD. #270 remains Draft while
that integration and exact-head automatic CI are outstanding. The original
red #270 CI is not the fixed-source result above.

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

Before any mutation, the unmodified A+G source must pass both selected MATCH
cases, including final consumer credit and cleanup retry. Preserve A's complete
fix SHA, G's integrated SHA, source bytes/digests and the actual inputs/quantums.
Do not replace the success expectation with expected `ForeignCandidate`.

Use the existing bounded/nonzero-test wrapper for the two MATCH cases. Give
each isolated invocation its own `_build` and preserve its logs; dependencies
may be borrowed, but never mutate a borrowed target or the active checkout.
For each fault, retain the exact source patch, compiler/target, counts, exit,
assertion location/message and observed before/after quantities. Compile failure,
zero-test discovery, timeout, an unrelated failure or the known completion
refusal is not mutation detection.

Restore all mutated bytes and modes to the fixed source before the next fault.
Check restoration against Git and rerun the same selected cases with a fresh
test process in that isolated worktree. Only that restored success closes the
fault's acceptance. Existing normal/cancellation tests and target/frequency
obligations remain; JS mutation observations are not Wasm/native detection
evidence. No CI selector, workflow, new harness, ledger or product fix is added
by this preparation.

## Reuse guide for A/B/C/D

The fixed-source normal and mutation/restoration runs above establish this
finite JS example. Use the final adopted fix revision and exact submitted-head
CI for integration; #270 remains Draft until those prerequisites are met.

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
3. Reuse `close_graph_host_consumer` where the closing consumer has its own
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

## Candidate after #270 closes: existing TimeSeries Host case

The first candidate is `standard Host runs time series with two retained
consumers` in `src/query_integration/local_time_series_wbtest.mbt`. It already
uses the same Host task execution, managed completion, ledger and existing
`delayed_cleanup_provider` fixture. This is a candidate, not a migrated or
accepted second example.

Initial bounded delta: two whitebox-test files plus this review record. Rename
the existing exact-credit consumer-close function to a Host-neutral name and
replace the two duplicated consumer-close blocks (about 15 lines of lifecycle
operations and availability checks) with calls to it. Retain the independent
three timestamp rows, canonical named-Result identity/deadline assertions,
remaining-consumer availability, original setup and all time/overflow/capacity
boundaries. The existing false-only cleanup counter expects 2; do not apply
the MATCH false/error/retry helper's expected 3 calls without matching that
contract. No new generic scenario callback or operation switch is needed.

A producer-close-during-consumption scenario would be additional connection
work, not automatically inherited from two close-helper calls. Estimate/review
that separately once the acquired-input fix and Graph acceptance are complete.
There is no deletion or CI-time reduction claim yet; all four older retained
Host layouts identified by #131 remain untouched.
