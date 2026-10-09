# Set ORDER-window private scope

## Problem and contract

Baseline: `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.

With a checked `records` schema containing `id` and `aql_order_window_0`,
the following valid query failed lowering with `Expression(UnknownReference)`:

```sql
SELECT * FROM records
UNION ALL SELECT * FROM records
ORDER BY ROW_NUMBER() OVER (ORDER BY id) DESC
```

The parser reserves synthetic window names against all authored name tokens.
However, star projection introduces checked schema names which need not occur
in the source. Set finalization exposed both the synthetic window reference
and the user column under the same logical name. Uppercase schema names also
require case-insensitive physical slot collision checks.

`append_set_final_steps` now allocates the private physical slot using the
existing case-insensitive allocator and resolves parser-owned ORDER-window
references before schema-only names in that output scope. All original columns
remain in the final projection. OVER input keys still resolve against the set
input schema. Explicit authored names cause the parser to choose a different
private reference, so user references are not reinterpreted as window outputs.
No checker, execution Owner, set multiplicity, grammar or pinned contract changes
are needed.

## Independent expectations

The focused MoonBit tests contain a hand-authored append/window/sort/projection
Program and the complete expected final Stage. They cover lowercase/uppercase
schema names, explicit OVER keys, scalar window expressions, secondary user
ORDER keys, script routing and exact unknown-private-slot refusal.

The existing packed ORDER-window corpus adds nine positive cases and one
refusal, without a new consumer or test-side Program mutation. A typed array
parameter supplies the star schema in public source. Independent JSON controls
use ordinary Values, derive, unnest, append, analytic, sort and select steps.
For input `(id=2, user=10), (id=1, user=90)`, the expected public rows contain
two copies of id 2 followed by two copies of id 1. Sorting by the colliding user
column instead would reverse that order. The public user column remains nullable
and precedes id; the private sort column is absent. Additional cases cover DATA,
NULL, empty input and duplicate rows. Unbound private slots must be rejected
before Run admission and provider I/O. Source acquisition counts are zero for
these parameter-only cases.

## Focused evidence

All evidence paths below are relative to the working checkout unless absolute.

- Pre-fix main reproduction: 0/1, `UnknownReference`;
  `_build/local-checks/attempts/run-csCRW7`,
  `_build/focused-evidence/focused-test-NeF2NX`. This is lowering evidence,
  not an executed public Run failure.
- Repair and affected callers: 17/17 JS;
  `_build/local-checks/attempts/run-pTiF1c`,
  `_build/focused-evidence/focused-test-QhIbZJ`.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/set_window_private_scope_test.mbt src/query_program/set_order_expression_test.mbt src/query_program/order_window_expression_test.mbt`.
- Fixture/ordinary-consumer registration: 3/3 Node;
  `_build/local-checks/attempts/run-eoSXS8`,
  `_build/focused-evidence/focused-test-6Ffxjz`.
  Command: `node scripts/local-checks.mjs test node -- scripts/order-window-source-input.test.mjs`.

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used. Formatting and
`git diff --check` passed.

## Pristine packed public acceptance

Clean source commit: `2a36c3e8686dc25c422391bb6c2c3f4f64e534bb`.
The subsequent evidence-only commit does not relabel these results as execution
of the submitted HEAD.

Commands, under the existing serialized heavy guard:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-set-window-private-2a36c3e86-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-set-window-private-2a36c3e86-pack node scripts/test-packed-public-query.mjs --order-window-only
```

Both Local and HTTPS completed **23 positive / 8 refusal cases**. The independent
JSON controls and all nine new positive cases passed. The hidden-slot refusal
returned `ClientProgramInvalidInput` with no Run admission or Source I/O.
The existing consumer verifies rows, declared column order, full types and
nullability, stream completion, request replay and rereading, with unchanged
installed ceilings. This is one ORDER-window cohort, not all frontend acceptance.

Original receipt and logs:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-PET7CJ`.
Guard: `_build/local-checks/attempts/run-qMvtXz`.
The receipt is complete/passed, clean-source revision matches the producer
manifest, all ten commands completed with exit zero, and there are no evidence
errors. An independent SHA256 calculation matched every manifest and receipt
digest. The temporary installation was removed after preserving the evidence.

| Package | SHA256 |
|---|---|
| client-wire | `ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60` |
| sdk | `64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e` |
| run-host-core | `f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54` |
| local-node | `0f0270d3273d12ab2c66a28bc777e927081b19a7323fdc6096ca53e1c45cf934` |
| node | `a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb` |

Exact submitted-HEAD CI, Wasm/native tests and full Core/packed coverage remain
unverified. No manual CI rerun or merge was performed.
