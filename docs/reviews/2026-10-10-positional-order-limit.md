# Positional operands with explicit ORDER and LIMIT

## Boundary and counterexample

The frontend rejected an anonymous positional right operand when its terminal
SELECT was followed by column-preserving ORDER or LIMIT:

```sql
SELECT 0 AS a
UNION ALL
(SELECT -x FROM t ORDER BY x DESC LIMIT 1)
ORDER BY a
```

For independent input `x = 1, 2`, the inner order selects `x = 2`, so the
answer is `[{"a":-2},{"a":0}]`. Sorting the evaluated `-x` instead would
select `-1`; dropping the limit would publish an extra row. An anonymous
`ROW_NUMBER() OVER (ORDER BY x)` in the same position was also refused.

At integrated baseline `09afb5195a9553069826d83831661df5eebfad84`, the preserved
three-case test reported one checked independent JSON control and two
`UnsupportedProjection` failures. Evidence: `_build/local-checks/attempts/run-uhSs0e`
and `_build/focused-evidence/focused-test-9m0m0j`. This is a compilation failure,
not evidence of incorrect rows from an executing Run.

## Repair

`compile_steps` recognizes the last SELECT through trailing ORDER and LIMIT.
Its existing aggregate, analytic and scalar projections retain separate
evaluated slots until ordinal set alignment supplies the left output names.
Existing ORDER resolution and LIMIT lowering remain responsible for evaluation,
aliases, qualified input references and parameter expressions.

Private physical column names are not authored aliases. ORDER rejects references
to those generated output names, including quoted and property receivers.
Duplicate aliases remain ambiguous, while ordinal references retain each value.
The same prefix resolver used by ordinary ORDER distinguishes a qualified input
range from a property receiver. This does not grant anonymous exports to authored
CTEs, public outputs or name-matched sets.

No parser, checker, planner, execution owner, budget, wire contract or pin is
changed. D's CTE/predicate/assert/Effect lowering is not edited.

## Independent evidence

The ordinary JSON control derives `neg`, sorts input `x DESC NULLS LAST`, takes
one row, projects it to `a`, appends the left zero and sorts final `a ASC`.
It is authored independently and checked through the ordinary checker. Source
tests also require the explicit sort/take fields and one evaluated negation.

Public fixtures add nine normal cases and four exact invalid-input refusals to
the existing normal and narrow packed consumer. Expected rows, column order,
types and nullability are authored independently. Controls distinguish input
order, ordinal order and output-alias order; retain parameterized OFFSET; and
cover anonymous windows, nullable SUM, COUNT and repeated aliases. The ordinary
consumer checks actual `Result.describe()`, private-column absence, one Source
acquisition, same-request reattachment and no admission/I/O for refusal.

The selected local guard `run-Wb5IPy` passed 22/22 JS tests across the changed
file and three direct caller files, plus 44/44 Node fixture/inventory tests.
This is local evidence before final main integration, not CI or packed execution
evidence. Earlier diagnostic runs `run-eM7K5n` and `run-bN0jmp` corrected an
incorrectly assumed private slot suffix and selected the public script refusal
boundary; they do not represent new product failures.

The authored inventory contains 3,378 occurrences (2,141 normal, 1,190 refusal,
47 execution-failure cases); its digest is
`b42f3382c3d4e4088513dca089376747a171c7b3bde330fc23ae05869b444f0f`.
This inventory identifies registered fixtures; it does not claim their execution.

## Remaining verification

After adopting the merged parent from main, fix a clean submitted SHA and normally
produce the five runtime packages. Execute the existing selected 95-case
Local/HTTPS cohort and record source revision, tarball digests and terminal
consumer evidence in the PR body. Until that succeeds, public execution for this
unit remains unverified. Full CI, Wasm/native execution, the complete packed
corpus and broader frontend completion are separate obligations.
