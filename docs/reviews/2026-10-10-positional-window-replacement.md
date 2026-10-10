# Window replacements over positional Pipe input

## Independent counterexample

At `53d45bbe5d242c02b8dddcc6138a17e11451b66f` (#1297), this source refuses
with `UnsupportedProjection`:

```aql
SELECT 0 AS a, 0 AS b
UNION ALL (
  FROM t |> SELECT x AS kept, -x
  |> SELECT * REPLACE (ROW_NUMBER() OVER (ORDER BY kept DESC) AS kept)
)
ORDER BY a, b
```

Independent x=1,2 gives (a,b)=(0,0),(1,-2),(2,-1). An authored ordinary JSON
control derives negation, projects kept/neg, computes row_number using kept,
projects rank/neg, appends zero and sorts. The control passes the common
checker. Baseline guard `run-nz744s` is 1/2; the saved source is
`/private/tmp/actql-b-positional-window-replacement-53d45bbe5-baseline.mbt`.
This is a text-lowering refusal, not an executing Run's observed wrong result.

Existing `docs/spec/query-text.md` connects star REPLACE to ordinary analytic
semantics using its input snapshot. GoogleSQL reference
`d82db99a923a46571f543a13899dc791a7b6f743` supplies the selected star REPLACE
and window contracts. No new syntax, analytic law or execution owner is added.

## Minimal frontend connection

The backward positional-role search stopped at the parser's analytic step
between two SELECTs. Analytic steps retain their input columns, so traverse
them to retain the earlier projection's anonymous ordinal roles. Check both
direct and expression-bearing analytic projections against current authored
names using existing private-name and duplicate-reference guards. Lower the
actual window through the existing analytic resolver/checker.

Private anonymous receivers remain UnknownColumn, and duplicate authored
receivers remain AmbiguousColumn. A simple window ORDER reference to a dropped
input/range uses the existing `query_analytic_order.mbt::analytic_order_field`
UnknownColumn diagnostic. An initially authored assertion expected the scalar
UnknownReference wrapper instead (`run-DrlOej`, 4/5); it was corrected from
that existing resolver contract, not by weakening a successful result.

## Focused checks and public obligations

The five JS steps of `run-bX6GwO` pass 29/29 tests: window replacement, scalar
replacement, exclusions, anonymous terminal windows and duplicate windows.
That guard's Node step failed because the old fixture test's substring selector
also selected new window replacement cases. Its overall guard remains failed.
The source was unchanged while the fixture families and selector were made
explicit. Final Node guard `run-jVxK7r` passes 49/49, with terminal exit 0,
complete output/caller output and released locks. Formatting and
`git diff --check` pass. Do not describe the failed combined guard as passed.

Six normal public fixtures cover independent JSON, direct source, an expression
containing a window value, a named window followed by a current-alias filter,
opposing simultaneous windows and typed empty output. Three refusals cover
private receiver names, dropped ranges and ambiguous authored inputs.
Expectations are authored independently: rows/order, column order, number
types/non-nullability, Source count and same-request reuse. Refusals must precede
Run admission and provider I/O. No acceptance-side Program patch is allowed.

The selected public cohort is 161 cases per transport (104 normal, 57 refusals).
The data-only full inventory is 3,444 obligations: 2,182 normal, 1,215 refusals,
47 execution-failure cases; digest
`a26a6bda96201df94e2b373b800ec766d1863f1fd3740f19e84abd077f240e62`.
This records registration, not full-corpus execution.

This is a separate branch stacked on #1297. Exact-SHA normal five-package
Local/HTTPS acceptance is pending. No old SHA's execution is attributed to this
source, and checker success is not execution completion. No full Core,
Wasm/native, proof, performance, full packed or Cloud campaign was run. The
broader frontend goal remains active; other owners' execution contracts and
CTE/assert/Effect work remain unchanged.
