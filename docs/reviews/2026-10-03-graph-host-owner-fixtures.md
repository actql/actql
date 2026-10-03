# Graph Host owner fixture reuse: integration status

Baseline: `b18632b65570713e36c0a83e8afd0063bc37a5c3` (`origin/main` when this worktree was created).
Branch: `test/graph-host-owner-fixtures`.

## Scope and reuse

The two added cases use the existing keyed Graph Host fixture for MATCH nodes
and MATCH edges. Existing normal cases, all nine variants at quantum 1, 7 and
1024, and the existing cancellation case remain. The new cases also run each
of those three quantum values. No workflow, history validator, product source,
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
Cleanup false and error preserve the reservation and holding. After the first
consumer closes, the second consumer and upstream outputs remain available;
the second consumer's exact rows are read again. After both consumers close,
upstream closure and execution disposal precede successful scratch cleanup.
That retry returns reservation credit, preserves the remaining VALUES holding
and consumed transfer/work, and is idempotent. Final upstream closure leaves
execution/retention reservations and holdings at zero.

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

## Remaining mutation acceptance

Production mutations remain unexecuted: early scratch release during pending
cleanup, double holding credit, and release before the remaining consumer ends.
Each must be exercised separately in an isolated copy, with
failure at the corresponding intermediate invariant and restored success.
Final-zero alone is not the double-credit detection criterion.

The original cases kept the producer port open until both consumers closed.
The two MATCH pilot cases now close it while the second consumer has no output
and still needs input. Holding is preserved and execution reaches independent
expected rows and finalization, but Host completion rejects with
`Execution(ForeignCandidate)` because the producer's public slot is gone.
The success expectation is retained. See the
[acquired-input handoff](2026-10-03-graph-host-acquired-input-handoff.md) for the
fixed counterexample, exact observations and A's separate product-fix boundary.
Existing normal cases remain unchanged. Mutation and exact-once cascade-return
acceptance await that fix; a failing unmutated case is not restored success.

Mutation detection is incomplete. Wasm/native execution, broader validation,
and exact submitted-SHA CI remain pending.
No existing tests have been removed.
