# Stop-only pause correspondence reuses common chain guarantees

## Scope and preserved obligations

This unit starts from main `a831ef94637992fc4298a38327e3ef7d0c6dfcb2`.
Implementation: `2cf51f3b3d6171de17c21b3490a235f29ab3f28a`.
Clean executed source and retained-history declaration:
`5891308325e6c832e08b337be03f40e0a0f2dce2`.

The existing chain already forwards `Waiting` and `Settling` during stop-only
polling. The old stop model and six-case connection excluded these zero-work
pauses. This change closes that finite connection obligation using the existing
accounting/responsibility laws, rather than creating per-operation stop matrices.

`StopAccounting.lean` adds a tagged pause event with a bounded work delta and
an unchanged productive state. The existing 14 theorem propositions are exact;
their induction cases now also admit pauses. Four new typed laws establish pause
reporting, zero-work identity, an admissible finite trace and its independent
numerical witness. `Chain.lean`, `Claims.lean`, Session model/claims, product
chain/provider owners and the old delayed-stop fixture are byte-identical to
adopted main. The checker retains all prior type and axiom checks and runs 54 laws.

The new two-case fixture uses the actual registered chain and common provider
owners with a diagnostic child. Explicit cancel and productive budget exhaustion
both observe `Waiting(0)`, `Settling(slot=7,work=1)`,
`Settling(slot=7,work=0)`, then a zero-work physical-stop observation. The exact
child charges are `[1,0,1,0,0]`, total 2; the exhausted productive budget is 1.
At each pause the child stays held, parent remains nonterminal, child cleanup
has not run, and there is exactly one start/Compute/cancel. The final stop keeps
custody through cleanup false/error/true. Repeated successful cleanup does not
call the child again. A holding marker is callback-custody evidence, not a
physical allocation measurement or Model/Store authority proof.

`registered-child/stop-pause` has independent, fixed execution coverage, its own
run/fixture and target. It reuses the common model root. The old six-case record
cannot be relabeled as this execution. Existing three prompt-stop scopes and the
old delayed-stop scope remain separately accepted. The normal runner adds this
fixture for each selected target without removing any existing fixture.

## Original local results

The first working-diff Node selection ran 47 cases: 46 passed, one failed.
All eight actual Lean tests passed, including the 54-law checker and six
weakened stop propositions rejected by real Lean. The failing source-route
negative found a weakness in the new connection gate: a matching productive
branch could hide removal of forwarding in the stop-only branch. The gate now
extracts that exact stop branch before checking the route. A focused rerun of
only the affected evidence gate passed 39/39. These working-diff records are
preserved and are not reported as clean-SHA execution.

Commands (pinned Node 22.22.0; explicit installed pinned Lean 4.30.0-rc1 on PATH):

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  proofs/relation-chain/evidence.test.mjs \
  proofs/relation-chain/proof-check.test.mjs
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  proofs/relation-chain/evidence.test.mjs
```

At clean source `5891308325e6c832e08b337be03f40e0a0f2dce2`, the existing
`proofs/relation-chain/run.mjs js` completed under `run-FivSdN` (360-second
shared-heavy budget, 5-second TERM grace):

| Boundary | Result | Duration |
|---|---:|---:|
| Actual Lean checker, proposition types, axiom audit | 54 laws | 22,655 ms |
| Existing Session fixture | 7/7 | 1,225 ms |
| Existing prompt-chain connection | 4/4 | 42,803 ms |
| Existing delayed-stop connection | 6/6 | 2,479 ms |
| New pause connection | 2/2 | 1,533 ms |
| Actual final graph consumer | 5 conditional claims | accepted |

The archived original JS report binds the clean source snapshot, compiler pin,
commands and generated test artifact digests. Final validation checked the
artifacts at the same source. These are local debug JS artifacts, not release
packages or an authenticated Actions original. No product fault injection was
performed: source/claim substitutions and weakened Lean propositions are
controlled negative inputs, not physical mutation experiments.

The exact bounded commands for clean-source checks are in the guard receipts.
The history check is read-only, with no `--write` or retained-original rewriting.

## Trust and remaining work

This is model proof plus finite correspondence, not verification of arbitrary
provider implementations. Actual Model/Store authority, slot/schema validation,
invalid-report/overflow behavior, physical capacity, early scratch retirement
and eventual stopping remain independent obligations. Wasm/Native execution,
full Core, packed/public acceptance and hosted CI were not run here. Normal
three-target integration coverage remains required; it is not inferred from JS.

No old test is retired, no production owner or workflow is changed, and no CI
reuse authority is expanded. Actions original authentication, compatible later
main qualification, ordinary PR `mutations-js` reuse, related-input fresh
execution and authentication/transfer-inclusive net savings remain unverified.

## Retained-history acceptance and original archive

At the same clean executed source, actual read-only
`node proofs/relation-pipeline/history.mjs` passed under `run-JuA8b3`
(240-second shared-heavy budget; complete streams; exit 0; locks released).
It composed 245 declarations, 199 integrations and all 89 protected files,
including this change's six protected verification files with real parent
blob digests and modes. The original output is preserved, not regenerated or
relabelled at a later publication SHA.

Archive: `evidence/2026-10-08-chain-stop-pauses-589130832.json.gz`.
It contains the initial failed Node result, subsequent gate success, actual
Lean/JS scientific report and logs, actual history manifest, guard/focused
receipts, source modes/digests and exact generated JS artifact correspondence.
The generated test binaries stay in the own worktree; this archive stores their
validated digests, not binary bytes or a complete runtime inventory.

Raw JSON: 4,023,189 bytes, SHA256 `b266333a2ded3fab0ffb17c20cfb84184182e8a71eae8d50bc05e47a826178ab`.

Gzip: 586,038 bytes, SHA256 `807c019bdf1e1528a468ff5aa98fe4e9614b23d131d33dbf82ba5efd8aee7b43`.
