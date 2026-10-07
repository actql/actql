# Stop-inclusive serial chain evidence

Original adopted main: `cb37bf04ce000ee2081fee0e64ee692a3c488d7c`.
Latest normally merged main: `dde7cca123b161d41e9a1e2b1093cb7cb49b611e`.
Clean integrated execution candidate: `9ef6fc36c30e645de3f616ae832e3e52af95325d`.
Implementation: `71eed489897df9e56984c84a6ae18493b00e6bca`.
Declared execution candidate: `8ce02b8056e5423b77fdc99fdfeca006a6b4e583`.

## Shared guarantee and scope

The original chain model admits prompt zero-work stop only. Its hard reported
work bound cannot describe the real exhausted-budget diagnostic with productive
budget 1 and accepted physical work `[1,1,1]`. The additive `RelationChainStop`
model reuses all original productive-state accounting/responsibility laws rather
than weakening those 22 laws. It adds fourteen audited laws for finite stop-only
traces: request is not physical stop; accepted terminal stop work is charged;
productive budget does not reopen; requested stopping cannot call Compute or
start a successor; pending cleanup retains the same obligation.

The concrete legal witness reports 3 while used/budget remain 1, with one Compute
entry and one stopped but still owed child. Stop-inclusive work is diagnostic,
not successful billed work or a productive admission upper bound. There is no
stop liveness assumption. Naturals represent accepted representable reports;
integer overflow, invalid-report sticky errors, zero-work Waiting/Settling,
early scratch retirement and capacity/physical destruction remain outside the
model. These limitations are not erased by a successful finite fixture.

The existing runner and evidence graph require a separate scoped delayed-work
fixture execution for each selected target, beside all original prompt-stop
claims. Six independently authored real cases cover final delta, terminal zero,
stop confirmed before a rejected extra poll, invalid accounting, the completed-
only accessor and standard managed-driver failure/cleanup. The diagnostic child
is not described as a bounded Session adapter. The new claim uses the executed
model and its exact own connection; it does not borrow prompt-stop applicability.
No original test, resource gate, model proposition or action is retired.

Main's completed-input binding has moved into its metadata cursor. The old
symbol-in-one-file guard was stale. Current route guards check predecessor
selection, receiver owner/step/port, output identity and read/cancel routing in
that owner. Source guards are finite reviewed connection premises, not a proof
of arbitrary implementation behavior. Wrong step/port/predecessor routes fail.

## Limited local diagnostics

The real pinned Lean checker passed all 50 laws (14 Session + 22 existing chain
+ 14 stop-inclusive), exact consumer types and permitted-axiom audit.

```sh
PATH=/Users/t14i/.elan/bin:$PATH node scripts/local-checks.mjs test node \
  --timeout-seconds 240 -- proofs/relation-chain/proof-check.test.mjs \
  proofs/relation-chain/evidence.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  proofs/relation-chain/evidence.test.mjs
```

The proof selection passed 6/6, including four deliberately weakened conclusions
rejected by actual Lean. The final evidence selection passed 30/30. They record
the working implementation on adopted main, not a later clean execution.
Initial diagnostics were 30/32 (stale binding guard) and 35/36 (a new negative
fixture's source fragment appeared twice). Both were corrected; raw failures
are retained. No failing count is replaced by a later source label.

After the normal main merge, the affected evidence selection passed **30/30**
at clean `9ef6fc36c30e645de3f616ae832e3e52af95325d`, guard `run-cUzkaj`.
The proof files/checker did not change during the merge; the actual JS runner
will check the same 50 laws at its own clean execution revision.

## Clean integrated JS acceptance

At `9ef6fc36c30e645de3f616ae832e3e52af95325d` (`worktreeDirty: false`),
the existing `node proofs/relation-chain/run.mjs js` completed under the shared
heavy guard (`run-cBsm9B`, 600-second bound; locks released). The pinned
MoonBit/Lean toolchains were used without Actions impersonation.

| Executed boundary | Result | Runner interval |
| --- | --- | --- |
| Typed Lean propositions and axiom audit | 50 laws | 11,845 ms |
| Existing bounded Session package | 7/7 tests | 764 ms |
| Original independent real chain connection | 4/4 tests | 35,080 ms |
| Existing registered delayed-stop/standard driver connection | 6/6 tests | 1,704 ms |
| Actual derivation consumer | Four conditional claims accepted | Included in whole guarded execution |

These are local verification durations, not a performance or CI-saving result.
The source snapshot is
`1a0ffc757aa026fa433b7b003d17b648f4528de8388427b06ebd8b593ff7281f`.
The report retains exact JS test artifact digests. Both connection executions
used the same unchanged query-integration artifact bytes, checked again by the
final consumer. Independent fixture values, budgets and cleanup assertions
were not rewritten.

## Retained-history failure, distinct from local runtime execution

At clean candidate `8ce02b8056e5423b77fdc99fdfeca006a6b4e583`, guard
`run-TBHSH2` executed the actual history consumer once and failed on the existing
main merge `a51ebdf215a27d661a310834a7fa7a606c4c40ac` (parents
`8566ff8083376bc8d9f3be458a0b3e3c9f56e385` and
`1e6684914d208dd111baba951618cac0beeb8a00`). It reported undeclared protected
changes in package.json and ten pipeline files. The second runtime step never
started. This failure is not Actions billing and is not waived. The read-only existing
consumer was executed again after the main merge at clean `9ef6fc36c30e645de3f616ae832e3e52af95325d`
(`run-Zb7xmf`, 90-second bound). It failed on the same inherited merge after
52.3 seconds, before any acceptance manifest was produced. Both raw failures
are retained. The later command is `node proofs/relation-pipeline/history.mjs`
without a write argument; no history, declarations or generated manifest was
modified.

An automatic approval review rejected a combined result-read/history `--write`
invocation because it could change retained history/declarations/generated
state. No process started for that rejected invocation. The existing read-only
consumer above was used instead; the rejection was not bypassed.

This PR records exact actual-parent/blob/mode declarations for its own six
protected source changes. It does not assert that the inherited whole history
passes. The integration owner needs to supply the main merge's actual declaration
before complete pipeline acceptance can pass. No history validator was relaxed.

The next independent JS attempt (`run-7XaP70`) was refused before execution
because D's live supervisor held the shared heavy lock. It ran no tests and is
not a performance failure. A second attempt (`run-vq8ypf`) was also refused before execution after B
acquired that lock. No lock, process or other owner's evidence was altered.

## Existing physical mutation runner: explicit remaining correspondence

A read-only source observation at `8ce02b8056e5423b77fdc99fdfeca006a6b4e583`
found no current occurrence for `reset-consumed-budget` and
`omit-handoff-accounting`. Two other substitutions still name the old `current`
and `children` references rather than the aggregated current state. This is a
separate existing runner repair, not nine successfully executed mutations.
No compiler rejection or missing site is counted as assertion detection.
The raw observation is retained and none of the existing four real prompt-stop
fixture expectations is changed in this PR.

## Remaining acceptance

JS acceptance is closed for the exact clean execution above. Native/Wasm and
full hosted coverage, the existing physical mutation campaign, complete capacity
bounds, successful Actions main originals, protected cross-main qualification,
ordinary-PR reuse and net CI savings remain separate. This work grants no reuse
permission, starts no Actions and performs no merge. Existing pipeline isolated
originals and #887 Native evidence remain unchanged and are not relabeled as
this revision's evidence.

## Preserved originals

[Compressed local original evidence](evidence/2026-10-08-chain-stop-accounting-9ef6fc36c.json.gz)
contains the unmodified clean JS report, guard summaries/output, Lean and target
logs, working-source diagnostics and original failures, lock refusals and the
read-only mutation-site observation. Test binary bytes remain in the guarded
local build; their path, byte size and SHA-256 are recorded in the archive, not
misrepresented as a distribution included in this text archive.

Raw JSON: 795,766 bytes, SHA-256 `231e39676999efb540012e1f0dabe9d8e9dcd77cbd74d8de88309cd7244ec3e1`.
Gzip: 224,776 bytes, SHA-256 `45ed649712967a8ba24561e121e749a90a5ac2cfafb0ce1c3dbd284b45210070`.
