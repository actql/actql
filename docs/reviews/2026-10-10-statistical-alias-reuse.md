# Statistical aggregate aliases and evaluated-slot reuse

## Existing contract and counterexample

Base: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
`docs/spec/query-text.md` already adopts `VARIANCE` as `VAR_SAMP` and `STDDEV`
as `STDDEV_SAMP`. The pinned GoogleSQL checkout
`d82db99a923a46571f543a13899dc791a7b6f743`,
`docs/statistical_aggregate_functions.md`, records the same aliases. This change
does not add a new statistical profile or change the common numeric laws.

```sql
SELECT DISTINCT VARIANCE(amount) AS v
FROM orders
ORDER BY VAR_SAMP(amount)
```

Before the fix, both calls lowered to `var_samp`, but reuse compared their
authored function names. ORDER received a second hidden aggregate slot, which
was absent after DISTINCT, and compilation returned `UnsupportedOrdering`.
The independently authored complete Values Program checked normally; the
same-name control passed before the alias variant failed. Evidence:
`_build/local-checks/attempts/run-hBbXgv` and
`_build/focused-evidence/focused-test-nxTaFF`. This is compiler evidence,
not a claim of a pre-fix public Run failure.

## Change and independent obligations

`compile.mbt` shares a closed aggregate-name mapping between lowering and
aggregate reuse. The compared argument/filter scopes, DISTINCT modifier,
delimiter and aggregate ordering remain unchanged. COUNTIF's conditional
DISTINCT rewrite remains distinct from COUNT's input contract. No checker,
execution Owner, grammar, numeric profile, schema pin or canonical law changes.

The new MoonBit fixture compares complete independently written Programs in
both alias directions, including quoted mixed-case names. Different sample
and population functions, arguments, filters and output-alias value slots
continue to return exactly `UnsupportedOrdering` after SELECT DISTINCT.
Existing aggregate receiver and COUNTIF DISTINCT tests remain selected.

The normal public statistical corpus now includes an independent JSON Program
and five SQL alias variants. Groups contain values [1,3], [0,4], NULL, and a
second [1,3]; sample variance yields ordered DISTINCT rows
`[{"v":2},{"v":8},{"v":null}]`. Sample deviation yields
`[{"v":sqrt(2)},{"v":2*sqrt(2)},{"v":null}]`.
An `id=0` row must remain excluded. The Result has exactly one nullable-number
column `v`; group keys and hidden ORDER slots must not be public columns.
Each source-backed case requires one source session. Different aggregate
functions/arguments remain explicit preparation refusals with no Run admission
or source I/O. The existing harness also checks Result description, resubmit,
reattach and no additional acquisition on Result rereads.

## Bounded verification

- Focused JS: `node scripts/local-checks.mjs test moon -- --target js
  src/query_program/statistical_alias_reuse_test.mbt
  src/query_program/statistical_aggregate_test.mbt
  src/query_program/aggregate_member_call_reuse_test.mbt
  src/query_program/countif_distinct_test.mbt`: 17/17;
  `run-YBkGb8`, `focused-test-k1lYiU`.
- Targeted Node: `node scripts/local-checks.mjs test node --
  scripts/statistical-aggregate-source-input.test.mjs`: 4/4, including explicit
  public refusal-code assertions; `run-R2XbUx`, `focused-test-jBl9zV`.
- Exact-commit normal five-package production and focused
  `node scripts/test-packed-public-query.mjs --statistical-aggregate-only`
  Local/authenticated HTTPS acceptance are pending at this source commit.
  Expected cohort: 20 successes, 10 preparation refusals and one expected
  execution failure per transport. Their results and tarball digests belong in
  the PR body after execution, without amending the verified source revision.
- No full Core, Wasm/native runtime, full packed campaign, Google service
  differential run or hosted CI success is claimed.
