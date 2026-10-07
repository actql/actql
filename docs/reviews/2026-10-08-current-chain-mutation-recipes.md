# Current serial chain mutation recipes

Adopted main: `dde7cca123b161d41e9a1e2b1093cb7cb49b611e`.
Implementation: `d27ac33a68d76d9ada3b4aab585d5fcf147525bf`.
Initial declared execution candidate: `bd0343de4ef8ad0e913b8ce2b34a6c43913a9feb`.
Corrected implementation: `380efbc9ec289246bb313148d95b679190c384a1`.
Intermediate candidate: `a8836592445728cfea9ac994d6a056908bed86bb`.
Final clean declared candidate: `235de1675dd8decd73dcf096041a245b32365d0a`.

## Problem and source correspondence

The existing serial chain mutation runner could no longer execute its reviewed
nine mutations against the current aggregate state/input-preparation owner.
Two anchors were absent: the parameterless `start_next` signature and direct
`match start_next()` handoff. Two substitutions referred to removed `current`
and `children` refs and would fail compilation.

Bind budget reset to the actual parameterized next-child start, control-charge
omission to the actual pending input-preparation handoff, and cleanup reentry /
failed-handoff custody loss to `state.current` / `state.children`. The same
mutation meanings, suite, JS target, filter and independently authored fixture
expectations remain. No product source is permanently changed; no old recipe
fallback or new operator/failure matrix is added. Missing/nonunique sites and
compile failures remain execution failures, never assertion detections.

Read-only observation at the declared candidate confirms all nine distinct
recipes each have one current site and change source bytes. This is only
source correspondence, not nine successful physical mutations.

## Acceptance

The first guarded attempt (`run-cJ4t54`) was refused before execution because
an independent live integration verification held the shared heavy lock. It ran
no mutation and is not a performance failure. The other owner's lock/process
was not altered.

The first real campaign at the initial candidate (`run-pinFbF`) detected four
mutations through running assertions, then rejected the fifth as a survivor
(`handoff-failure-drops-children`, 4/4 unchanged tests passed). Its `finally`
restored the production source; the final healthy runner was not started.
This result is retained, not counted as successful detection.

The original recipe targeted the input-preparation error branch. The independent
failure fixture instead completes input preparation and reaches next-child
start rejection after four units of child work and its last control unit.
Move the same custody-loss fault into that actual `start_next(selected)` failure
branch. The retained-output, pending/error/retry assertions remain unchanged.
No product contract or fault detection criterion was relaxed.

The intermediate candidate executed the first four mutations again, then
rejected the fifth before execution: the new literal included a comma absent
from the actual MoonBit match arm. This failed guard (`run-yMYTOZ`) and its
original error remain retained, not counted as fault detection. Correct that
literal and preflight all nine sites before compiling any mutant. The per-site
check at injection remains too; no failing criterion is weakened.

At clean `235de1675dd8decd73dcf096041a245b32365d0a`, the existing nine-mutation
runner detected all nine faults through running fixture assertions, excluded
compile errors and verified the full source snapshot was restored. The combined
guard (`run-lD8qnj`) then failed in the healthy runner on main's obsolete
symbol-in-one-file binding guard, before healthy tests started. The failed guard
is not described as completely successful.

Adopt the already-reviewed scoped consumer from parent Draft #890 by normal
merge (parent `b2b64720849c84febb0dedab7b143451c87a3fb6`). This also adopts
reviewed main integration, including the inherited UNNEST declaration repair.
At clean `8257d11d6b9d64b4cf8bc9ded508604aaf56eec8`, guard `run-DxlULF`
passed actual Lean 50 laws/type/axiom audit, Session 7/7, original chain 4/4,
delayed-work connection 6/6 and the actual four-claim consumer. Its locks were
released. The mutation runner, both deliberately mutated production sources and
the independent four-case fixture are byte-identical between those revisions.
Other integrated inputs changed; the nine mutations are the original candidate's
evidence, not relabeled as fresh execution at the merged candidate.

| Existing mutation | Running assertion failures |
| --- | ---: |
| Reset consumed budget | 2 |
| Omit handoff charge | 2 |
| Give next child fresh budget | 1 |
| Cleanup reenters advance | 1 |
| Failed handoff drops child custody | 2 |
| Pending cleanup reported complete | 1 |
| Cancellation not forwarded | 2 |
| Adapter uses cumulative work as delta | 3 |
| Premature chain terminal | 3 |

The custody-loss fault fails the intermediate pending-cleanup assertion;
cleanup reentry fails the actual call-count assertion. This does not reduce
fault detection to final-zero state, timeout or compiler rejection.

## Scope and remaining obligations

The existing nine JS mutations exercise common prompt-stop accounting and
cleanup ownership through four unchanged real chain fixtures. They do not
establish arbitrary delayed-stop behavior, Native/Wasm fault detection,
complete capacity bounds or authenticated Actions evidence. The scoped final consumer is adopted from Draft #890, which is now the unmerged
parent dependency. Merge target remains main after that parent is adopted.

The inherited retained-history issue observed at fixed #890 execution is not
waived by mutation success. Its integration repair remains separately reviewed.
No Actions is started, original receipt is rewritten or reuse permission granted.

## Exact commands and preserved originals

```sh
node proofs/relation-chain/mutations.mjs
node proofs/relation-chain/run.mjs js
```

The existing shared heavy guard bounds each attempt, preserves nonzero tests
and does not impersonate Actions. Initial refusals ran no command. The accepted
mutation step and its initially failed post-restoration consumer remain in the
same unmodified guard output; the later scoped consumer has its own receipt.

[Local original archive](evidence/2026-10-08-current-chain-mutations-235de1675.json.gz)
contains raw reports/logs, original survivor and missing-site errors, guard
results, source identities and final JS artifact digests. JS artifact bytes are
retained locally and are not bundled into this text archive.

Raw JSON: 1,263,012 bytes, SHA-256 `2ed82e86887ca0784b030ff0bdcbc69543aae5e25be42562ab7a05371e03b945`.
Gzip: 422,606 bytes, SHA-256 `499490ae4f1deb189110b239e9c9c41f10dcd5486b6f71d009b1dc2ed8b68a68`.
