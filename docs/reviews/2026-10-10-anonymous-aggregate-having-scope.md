# Anonymous aggregate values are not HAVING names

## Counterexample and adopted boundary

Adopted main: `ab69cd06a94b1c5a998521435e61c9f201a5c9a9`, including merged
#1237 and #1238. No unmerged implementation dependency is required.

```sql
SELECT 0 AS n
UNION ALL
SELECT COUNT(*) HAVING aql_set_aggregate_0 > 0
```

The right operand has no authored output name. Its ordinal aggregate value is
valid, but its compiler-generated physical name is unavailable to authored
HAVING. The expected result is `Expression(UnknownReference)` and the existing
public checker projects `ClientProgramInvalidInput`, before Run admission or
Source I/O. This expectation is independent of the generated Program.

The previous `_1` refusal test addressed a different, absent slot. Correcting
it to actual `_0` failed 3/4 (`run-TdcSbg`, `focused-test-krhkfm`). A diagnostic
match then confirmed successful lowering, not another rejection: the generated
right operand contained group aggregate `aql_set_aggregate_0`, followed by
`filter: {gt: [{field: "aql_set_aggregate_0"}, {literal: 0}]}`. That focused run
also failed 3/4 (`run-KWlBb4`, `focused-test-NSUzkS`). The receipt contains the
actual complete Program. This confirms a lowering leak; it is not a claim that
a public Run with the old source was executed.

## Minimal repair and independent controls

Keep the anonymous aggregate as a physical value for evaluated-slot reuse,
terminal SELECT and ordinary ordinal alignment. At the end of GROUP lowering,
exclude those exact anonymous value slots from logical `pipe_visible` and mark
the scope as changed. HAVING then resolves through the existing scoped path
instead of treating all physical fields as authored names. Eight added product
lines in `compile_steps`; no new evaluator, checker exception, grammar, wire,
identity law, limit or execution boundary.

- Bare, case-varied and backtick references to the actual private `_0` each
  require `UnknownReference`.
- `SELECT COUNT(*) HAVING COUNT(*) > 0` remains valid.
- Explicit `AS aql_set_aggregate_0` remains an authored alias and valid HAVING
  input. Prefix spelling alone is not a reserved-name prohibition.
- Both positive sources yield sorted `[{"n":0},{"n":1}]`, with one nonnullable
  number column. A separately authored JSON Values/sort Program fixes that
  same public value/type/order expectation.

The existing PIVOT/aggregate public cohort retains all prior 20 cases and adds
three normal controls and three exact refusals (26 total). Cases also remain in
the ordinary packed corpus. The independent registration digest records 3,297
occurrences; no expected value was generated from product output.

## Executed verification

- JS aggregate/set and HAVING callers: 25/25 (`run-Vxl6iq`,
  `focused-test-aeDWEc`).
- Targeted PIVOT fixture and profile/inventory tests: 39/39 (`run-fWBznD`,
  `focused-test-Q881Me`).

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/positional_set_aggregate_test.mbt src/query_program/having_aggregate_test.mbt src/query_program/having_projection_slots_test.mbt src/query_program/having_grouped_subexpression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- scripts/pipe-pivot-source-input.test.mjs scripts/public-query-profiles.test.mjs
```

Normal five-package production and scoped packed Local/authenticated HTTPS
acceptance remain required at this implementation record. Preserve their
actual tested SHA, manifest, digests and transport inventories separately.
No full Core, Native/Wasm, full packed corpus or hosted CI success is claimed.
This closes one frontend scope defect, not the wider frontend goal.
