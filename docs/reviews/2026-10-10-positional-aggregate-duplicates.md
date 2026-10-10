# Duplicate aggregate aliases in terminal positional set operands

This frontend unit depends on #1251's ordinary projection repair at
`12695f48d8a06dc17059e9348ae9940d8c95c9ab`. Its initial adopted main is
`42e8ad04f391218bc4ee36f61fba99f89c0bd327`. The dependency remains explicit
until the parent reaches main. No common aggregate, Result, execution,
capacity, identity, grammar, or wire contract is changed.

## Counterexample and independently selected meaning

```sql
SELECT 0 AS a, 0 AS b
UNION ALL
SELECT COUNT(*) AS n, COUNT(CAST(NULL AS FLOAT64)) AS n
ORDER BY a, b
```

Independently expected rows are `[{"a":0,"b":0},{"a":1,"b":0}]`, with
two nonnullable numeric columns in a/b order. A source-free SELECT has one
input row. COUNT(*) counts it, whereas COUNT of the typed NULL excludes it.
The positional right aliases do not replace the first operand's public names.
The adopted GoogleSQL positional-set and duplicate-alias rules are linked in
[the parent record](2026-10-10-positional-duplicate-columns.md).

Before this repair the source fails lowering with `UnsupportedAggregate`:
`run-CIcpn4`, `focused-test-nVz6nw`, 0/1. This establishes a frontend
rejection, not an executed wrong result. The alias-only aggregate table finds
two entries for n and cannot identify which evaluated COUNT belongs to each
terminal SELECT occurrence.

## Connection repair

For repeated aliases in a terminal positional SELECT, GROUP creates distinct
physical aggregate fields and records their original AggregateCalls. SELECT
looks up each evaluated slot with the existing scope-aware aggregate-call
comparison, including arguments, filters, DISTINCT and aggregate ordering.
It then uses the parent's ordinal projection and alignment. COUNT(*) and
COUNT(NULL) cannot match merely because both have alias n or function COUNT.

These private fields do not enter the authored HAVING/QUALIFY scope. Duplicate
aliases cannot supply an ambiguous receiver. Existing prefix resolution keeps
qualified grouped inputs such as `n.x` as inputs rather than flattening them
to alias n. Common expression lowering retains property/type/NULL checks.
The repair does not promote public or BY NAME duplicate columns to supported
outputs, remove predicate/order conditions, or add an aggregate evaluator.

## Independent regression obligations

- A complete hand-authored DATA Values/group/select/append Program is compared
  to the generated metadata-stripped Program and checked normally. Both COUNT
  inputs and their distinct physical-to-ordinal bindings are fixed explicitly.
- A separate ordinary JSON control counts a single nullable numeric NULL by
  COUNT(*) and COUNT(field), then appends the left (0,0) row. This control is
  authored directly and does not call frontend lowering.
- Named/case-colliding aliases, WHERE FALSE, explicit HAVING COUNT(*), and a
  grouped qualified input receiver pass the ordinary checker.
- Bare, backtick and property-receiver ambiguous HAVING/QUALIFY references require
  exact `AmbiguousColumn`; actual generated private slot names require the
  common expression lowerer's `UnknownReference`.
- The existing normal and scoped packed consumer gain seven positive cases and
  four `ClientProgramInvalidInput` cases, all registered in the ordinary
  corpus as well. No product-generated Program is patched by the consumer.
  Rows, describe types/nullability/column order, hidden-field absence, zero
  acquisition for these source-free cases, same-request reuse, reread, and
  zero Run admission/provider I/O on refusal use the existing public checks.

The independent ordinary control initially omitted the mandatory alias on
its Values generator. Its rejection was traced to `GeneratorRequiresAlias`
(`run-AjIE49`) and corrected without changing expected COUNT results. The
complete structural expectation initially counted the hidden source-free
unit as a visible input. Physical naming reserves only the two visible
authored aliases, so aggregate indices are two/three, not three/four
(`run-yZ1gJL`). This structural correction does not change calls or results.

## Integrated clause-alias correction

Normal merge `dcda04f5d9af81aeb1ffa52575b54cca17addc16` adopts parent #1251
at `c0cd08d77849d4035aaabd534a4a13c86e755dfa` and main
`c00439f4f1d4b942e16e4eece97990866c3ec02e`. The inventory/count conflicts
were resolved from combined authored registration, keeping main's historical
sourceBaseline and every expected value. #1248 is now independently merged.

A further positive control adds ROW_NUMBER over a grouped input and qualifies
on that qualified input plus rn. The unreferenced duplicate COUNT aliases
caused `materialize_clause_aliases` to reject `DuplicateOutput` before SELECT
(`run-D2S0Gb`). The intended rows for a single x=1 are
`[{"a":0,"b":0,"c":0},{"a":1,"b":0,"c":1}]`, all nonnullable numbers.
This is a frontend clause-preparation rejection, not an executed wrong result.

The shared frontend alias-preparation helper now prepares only aliases actually
demanded by a clause, consistent with its existing scalar demand behavior.
An ambiguous demanded alias is rejected; a qualified input prefix keeps its
existing meaning. Analytic/aggregate outputs still reuse their evaluated slots,
and nested window-alias refusal stays in the same helper. QUALIFY uses this
ordinary helper rather than a separate duplicate check. No common evaluator,
scope evidence or window semantics change. The new qualified positive and
ambiguous negative are also ordinary public fixtures.

Final authored registration has 3,334 occurrences: 2,110 normal, 1,177 refusal,
47 execution-failure expectations; digest
`d8e982fca91519287b55cbd7ee44c5aa23f55725f48ce17e28b285c03c56d002`.
The scoped consumer has 51 cases: 32 normal and 19 refusal per transport.

## Executed focused checks and pending acceptance

- JS affected aggregate, HAVING, filter and positional callers: 36/36
  (`run-j5XbZF`, `focused-test-mJNwdo`).
- Final complete independent Program and actual-private-slot regressions: 5/5
  (`run-zhOvac`, `focused-test-NMrEgC`).
- Node fixture/inventory registration before the final private-slot fixture
  correction: 40/40 (`run-vHA2rY`, `focused-test-NwWRRO`). The final authored
  inventory is regenerated from fixture data, never product output; its
  final registration check follows integration.
- Integrated aggregate/QUALIFY/window-expression callers after the demand
  correction: 28/28 (`run-oaC6Nw`, `focused-test-EGiV5R`).
- Final integrated Node fixture/inventory checks: 40/40
  (`run-i6VFuV`, `focused-test-KzamrW`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_aggregate_duplicates_test.mbt src/query_program/positional_duplicate_columns_test.mbt src/query_program/positional_set_aggregate_test.mbt src/query_program/group_having_implicit_alias_test.mbt src/query_program/having_projection_slots_test.mbt src/query_program/aggregate_filter_scope_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_aggregate_duplicates_test.mbt
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_aggregate_duplicates_test.mbt src/query_program/qualify_test.mbt src/query_program/qualify_group_aggregate_slots_test.mbt src/query_program/order_window_expression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/set-corresponding-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

Exact-SHA normal five-package production and the existing
`--set-corresponding-only` Embedded Local/authenticated HTTPS consumer remain
pending when this source record is committed. Actual manifest/digests and
receipts will be recorded in the PR acceptance status after execution.
No pristine public execution, full Core, Native/Wasm or hosted CI
success is claimed for this unit. The shared heavy gate is respected, not
removed or bypassed. The parent scalar and this aggregate connection's
completion remain distinct from #1243's common JOIN capacity rejection and
the wider frontend work.
