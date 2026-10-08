# Existing lifetime assertions detect real retirement mutations

G; adopted main `ce6d529d43292733eaa1b6967fc4571627a4ea5c`. Implementation `5d7fdb0e89e16111fad48512821f55fd17b02230`; actual clean execution `491166a17cf7ba3cc03d24fb18cf01d4a5130e7b`. The common early-retirement law extension in #949 is separately reviewable and is not an unmerged dependency of this runtime evidence.

## Gap and reuse boundary

The product already has eight real intermediate-lifetime cases. The existing chain mutation runner used only the older four correspondence cases. Merely adding a formal retirement law does not establish that these real assertions catch a wrong production connection. This unit extends that same runner with three mutations of `reclaim_relation_chain_child` or its successor-admission call site. It uses the existing fixtures and Owners, without duplicating a protocol/operation/failure matrix.

| Actual production defect | Independently authored observation required |
| --- | --- |
| Skip the intermediate cleanup callback, then drop execution roots | `assert_eq(cleanups[before], 1)` in the built-in lifetime case: zero callbacks must fail |
| Invoke the callback twice after confirmed cleanup | The same authored callback count: two must fail |
| Continue successor admission after cleanup returns false | The pending-custody case's expected `Waiting` assertion must fail before next-child admission can count as success |

Each mutant selects exactly that one authored test. Admission requires one executed failed test, the expected case and source assertion location, and the runtime `FAILED` assertion diagnostic. A compiler error, timeout, signal, zero tests, unrelated assertion or unwrap panic is refused. Pure controlled-output negatives check this parser contract; actual MoonBit faults are separate evidence below.

The default workflow command still runs every original recipe, unchanged, and now these three as well (12 total). The explicit local `retirement` selection writes `mutations-retirement.json`, not the complete `mutations.json` report. All twelve source sites must be unambiguous before running even the local subset. Existing all-target final proof/runtime gates remain unchanged. This adds no reusable Actions action and removes no test.

## Executed local evidence

`node scripts/local-checks.mjs test node --timeout-seconds 60 -- proofs/relation-chain/mutation-retirement.test.mjs`: 13/13 working-source controls, zero skips; `run-IbboyI`, `focused-test-SdKEH6`. This does not claim physical mutations.

At clean revision `491166a17cf7ba3cc03d24fb18cf01d4a5130e7b`, bounded heavy guard `run-40EYGP` passed both steps (900-second budget):

- `node proofs/relation-chain/mutations.mjs retirement`: all three real mutants detected; before/after unchanged fixture 8/8 each. Omitted cleanup failed at line 310 (`0 != 1`); repeated cleanup at the same assertion (`2 != 1`); pending cleanup at line 424 (expected `Waiting` assertion false). No compiler error, timeout or unwrap panic was counted.
- `node proofs/relation-pipeline/history.mjs`: 266 declarations, 217 integrations, 27 supplements and 89 protected files accepted.

The mutation command elapsed 102.878 seconds; history 508.626 seconds. Normal observations were 49.161 and 14.289 seconds, including build/runtime observation; the three mutants were 7.588, 10.231 and 11.581 seconds. These are diagnostic durations, not a controlled savings comparison.

Source snapshot: `b34fa3c64f87a537c0cb79195f0493d88d785190d7d5cb582b29541866aaa6a2`. All 15 retained JS artifact references were read back and authenticated by bytes/digest. The before/after normal binaries were identical; the three mutant whitebox binaries had distinct digests. The original raw-log consumer accepted the actual witnesses, precise mutated/original/restored source correspondence and history.

The runner restores each exact source byte sequence in `finally` and verifies the broad source snapshot. Normal eight-case fixture observations before and after the new faults remain independent. Normal and mutated JS artifacts are retained separately, with actual source digests and compiler pin verification. The read-only original consumer reconstructs each mutant from its recipe, verifies mutated and restored source digests, requires the exact runtime assertion again, checks all binary-reference bytes/digests, and compares before/after normal binary identities. It does not obtain expected result values from the mutation.

The three changed protected files have a source/parent/blob/mode foundation declaration. Original recipes, immutable evidence and validator conditions are retained. Production source, runtime expectations, limits, workflow and models are unchanged at publication; only isolated mutation execution temporarily changes the source and restores it.

Original evidence archive: [`2026-10-08-chain-retirement-mutations-491166a17.json.gz`](evidence/2026-10-08-chain-retirement-mutations-491166a17.json.gz), SHA-256 `4cc2103e4787d90d3783e6760b36e696cf7fa3450289c2608d5fb8779256df61`; 467,027 compressed bytes, 30 exact text members and 15 retained binary references. The gzip round-trip, every text member's byte count/digest and its correspondence to the original local record were checked. Referenced binaries remain in the execution worktree's `.artifacts/relation-chain/retirement-artifacts/`; this text archive is not a binary distribution. Original revision and receipt identities remain unchanged.

## Scope and remaining obligations

This demonstrates three defects at one shared execution-retirement boundary on JS. It does not claim complete fault coverage, all branches in each parameterized case, physical freeing, universal implementation refinement, a peak-allocation bound or all-provider stopping. The existing healthy eight-case fixture retains the group/JOIN/Values/UNNEST expectations and its conservative-fallback, generation and cancellation checks. Other semantics, identity, algorithm/resource bounds and physical/provider contracts still need their own evidence.

The original nine faults, Wasm/Native runtime, packed/public physical acceptance, full final three-target audit and Hosted CI were not freshly run for this unit. The ordinary default remains mandatory; local subset success is not reported as its complete success. Source/library changes invalidate these source-bound observations.

No Actions original polling/dispatch/retry, Ready transition, merge or service writes. Compatible later-main qualification, ordinary-PR `mutations-js` reuse, related-input fresh fallback and retrieval/authentication-inclusive net savings remain the separate external unit. No savings claim is made for adding mutation coverage.
