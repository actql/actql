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
`git diff --check` passed. Packed Local/HTTPS execution and exact submitted-HEAD
CI are pending; focused tests do not establish either.
