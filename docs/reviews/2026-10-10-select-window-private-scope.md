# SELECT-window references and schema-only star names

## Reproduction and fix

Baseline: `040eed2b1a11a3d1f7bae81b68d956d1017fac05`.
Use a checked `records` schema with numeric `id` and
`aql_select_window_0`, and rows `(2,10), (1,90)`.

```aql
FROM records
|> AS r
|> SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos
|> ORDER BY id DESC
```

This failed lowering with `Expression(UnknownReference)`. The equivalent plain
SQL SELECT passed. Star introduces a checked input name absent from the source
tokens; the scoped SELECT expression table then contained both that user column
and the parser's private window reference under the same spelling.

The private expression scope now resolves parser-owned references separately,
while keeping the user column in the public projection and qualified input
ranges unchanged. Explicit user references remain protected by the parser's
existing fresh-name scan. No prefix is reserved as a user-language restriction.

The related `GROUP BY ALL` query exposed two further points in this same
identity boundary:

```sql
SELECT *, ROW_NUMBER() OVER (ORDER BY id) + 1 AS pos
FROM records GROUP BY ALL ORDER BY id DESC
```

Inferred keys wrongly excluded the schema column because its spelling matched
an internal reference. A schema-generated star-column reference has an empty
source span; retain it as an input key rather than treating it as an extracted
aggregate/window atom. Then, grouped-expression reuse must compare the private
SELECT reference's resolved window slot against the original key's input slot.
Passing the original input resolver for both sides reused the user column and
would compute `pos` as 11/91. The adapter now supplies distinct reference
meanings to the existing shared grouped-expression lowerer. Expected values
remain 3/2 in descending id order.

There is no checker, expression evaluator, execution Owner, grammar or contract
change. Public fields, GROUP key admissibility, NULL behavior, duplicate rows
and qualified range lookup retain their existing contracts.

## Independent expectations

- A complete hand-authored ordinary Values/analytic/derive/select/sort Program
  is checked independently.
- Lowering assertions require the add operand to be the separate analytic
  output. Two input fields plus the reserved SELECT alias `pos` yield private
  physical slot 3 under the existing allocator; no product output generates
  that expectation.
- SQL, Pipe and GROUP BY ALL retain `[id, user_column, pos]` in the focused
  generated-values tests. Uppercase schema spelling follows the same boundary.
- Authored OVER keys and qualified user-value operands have opposing `pos`
  expectations, so replacing a user reference with a private value is detectable.
- A subsequent SELECT of the private physical slot must return exact
  `Expression(UnknownReference)`.
- Twelve added positive public fixtures use an independently authored JSON
  Program and typed array parameters, including SQL, Pipe, GROUP BY ALL, named
  windows, NULL, empty input and duplicates. The public nullable user column
  precedes `id` and `pos`; rank plus a constant is nonnullable, while rank plus
  the nullable user value remains nullable. No private column is published.
- The existing normal and narrow window-scalar consumer both include these
  cases. One added refusal must occur before Run admission and provider I/O.

## Focused evidence

Paths are relative to the checkout unless absolute. `run-*` directories are
under `_build/local-checks/attempts`; `focused-test-*` directories are under
`_build/focused-evidence`.

- Pre-fix baseline: 0/1, exact Pipe `UnknownReference`;
  `_build/local-checks/attempts/run-m4prLR`,
  `_build/focused-evidence/focused-test-WK36ZE`. This is lowering evidence,
  not a public Run execution failure.
- Intermediate repair probes are retained: GROUP BY ALL `UnsupportedGrouping`
  at `run-DTx5NT` / `focused-test-nf2jNk`; independently asserted wrong grouped
  add operand at `run-S9RYSM` / `focused-test-nOANdw`. These used modified source,
  not clean baseline distributions. The expected values were not weakened.
- Final JS: 32/32, `run-dIgTIW` / `focused-test-yDOrhP`.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/select_window_private_scope_test.mbt src/query_program/analytic_output_scope_test.mbt src/query_program/window_scalar_projection_test.mbt src/query_program/pipe_select_named_window_test.mbt src/query_program/sql_group_by_all_test.mbt src/query_program/group_property_receiver_scope_test.mbt`.
- Node: 8/8, `run-7kdWjt` / `focused-test-8K8lPd`.
  Command: `node scripts/local-checks.mjs test node -- scripts/window-scalar-source-input.test.mjs`.
  The same command after the nullable fixture correction passed 8/8 at
  `run-JUNDbN` / `focused-test-G5XMwd`.

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used. Formatting and
`git diff --check` passed. Pristine packed Local/HTTPS execution and exact
submitted-HEAD CI remain pending. The selected window-scalar corpus contains
70 positive, 37 refusal and one deliberate execution-failure case per transport;
it is not the full frontend campaign.

## Initial packed fixture correction

The first pristine pack at `24c186540289c539889fea2a61dbc893f8061974`
stopped in Local at `schema-private-qualified-user-value`. Its independently
authored rows 12/91 matched, but the fixture incorrectly declared `pos` non-NULL.
Adding a nullable input field must keep a nullable result contract even when
this particular pair of rows has non-NULL values. Only that expectation is
corrected; the source, rows, ordering, ceilings and product implementation are
unchanged. The fixture test explicitly checks this declared nullable result.
HTTPS and subsequent cases were not reached in this initial run.

Original failed evidence is retained at
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-6nDxM7`;
guard `run-DJGqPE`, failure `010.stderr.log`. This is a fixture type-expectation
error, not evidence of an incorrect shared type rule. The source-specific
tarballs remain at `/private/tmp/actql-b-select-window-private-24c186540-pack`.
