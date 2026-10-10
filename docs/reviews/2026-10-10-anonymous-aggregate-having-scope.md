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

## Fixed-SHA public acceptance

Normal five-package production and scoped packed acceptance at
`5f64b7ddb43782a3633e213f5b9633c20042f811` passed (`run-eLIkn6`).
Embedded Local and authenticated HTTPS each completed 26/26 cases: all prior
20 cases, three positive controls and three private-slot refusals. Both
inventories matched `a0364a60cbe810d85a966c20cc611df7470ce6fff5d01199ad2ff473fbf975e1`;
both workers exited zero with no live children. Normal cases retain actual
Named Result values, describe type/nullability/column order, hidden-field
absence, resend/reread, and refusals retain zero admission and Source I/O.

Receipt: `worktrees/.codex-scratch/public-query-evidence-Z034sv/summary.json`.
The directory retains transport completion/process inventories and logs.
Private installs were removed after evidence retention (`artifactsRemoved:
true`, no evidence errors). Normal source manifest:
`/private/tmp/actql-b-anonymous-aggregate-scope-5f64b7ddb-pack/packed-client-packages.json`.
Independent SHA-256 checks matched every produced tarball:

| Package | SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | 5a40470f4533ac62c93909ca949c45e335bd056bac609e6eb8fbe8a894c4be0f |
| local-node | 14cde1b2b10f04940483356e6e51c71188ad153324dc350489e8b301c323587c |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-anonymous-aggregate-scope-5f64b7ddb-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-anonymous-aggregate-scope-5f64b7ddb-pack node scripts/test-packed-public-query.mjs --pipe-pivot-only
```

The existing wrapper pins Node/MoonBit and applies a 1,200-second aggregate
budget/exclusive heavy slot. This final evidence-recording commit changes this
document only; packed execution remains attributed to `5f64b7ddb...`.
Hosted CI and the broader unexecuted suites remain unverified. No merge was
performed and the wider frontend goal remains active.
