# BETWEEN public execution acceptance

## Scope and fixed baseline

Baseline: `584b3a6144d4a8053ca4a541ef042a6e17c674e9` (`origin/main`).
The common execution dependency `8085d4953` is already in that baseline.
This unit closes the public acceptance obligation for BETWEEN identified in
[the earlier predicate boundary report](2026-10-08-predicate-contract-boundaries.md).
That report's `ExpressionNotImplemented("between")` observation belongs to its
older inspected source, not to current main. LIKE remains a separate obligation.

No parser, lowerer, checker, expression owner, identity, grammar or pin is changed.
Existing public source already lowers BETWEEN to one ordinary three-operand node
and NOT BETWEEN to `not(between(...))`. Do not expand the tested operand into
multiple comparison subtrees or replace the common bounded executor.

## Independent meaning and examples

Selected reference: `google/googlesql@d82db99a923a46571f543a13899dc791a7b6f743`,
[operators](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/operators.md).
The [official operator reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators)
defines inclusive bounds and three-valued AND, with one evaluation of the tested
operand. The [conditional reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions)
defines branch demand for IF and CASE. This is not a differential run against a
Google service or a claim of full operator/type compatibility.

| Authored case | Required value or behavior |
| --- | --- |
| `1 BETWEEN 1 AND 2`, `2 BETWEEN 1 AND 2` | TRUE at both endpoints |
| `3 BETWEEN 1 AND 2`, `1 BETWEEN 2 AND 0` | FALSE; do not reorder bounds |
| `1 BETWEEN NULL AND 0` | FALSE, not blanket NULL propagation |
| `3 BETWEEN 4 AND NULL` | FALSE |
| `1 BETWEEN NULL AND 2`, `NULL BETWEEN 1 AND 2` | SQL NULL |
| `3 NOT BETWEEN 4 AND NULL` | TRUE |
| nullable `@p` set to 2 or NULL | TRUE or SQL NULL; same declared nullable Boolean |
| unselected IF/CASE branch contains failing BETWEEN | Success without demanding that branch |
| `1 BETWEEN 2 AND (1 / 0)` | Execution fails; FALSE lower comparison does not erase the upper expression |
| `(1 / 0) BETWEEN 0 AND 2` | Execution fails; no successful partial Result |
| WHERE BETWEEN over nullable acquired rows | IDs 1,2,3 ordered, including both equal amount=2 observations |
| Empty input | Empty Result with the declared nullable Boolean schema |

`scripts/fixtures/between-source-input.mjs` contains **11 successes, 4 preparation
refusals and 2 demanded execution failures**. Three successes are independently
written JSON controls, including acquired input and typed parameters. The same
fixtures enter the ordinary packed corpus and `--between-only` selection.
The existing public harness compares Named Result rows and `Result.describe()`
column order/contracts, repeats the request and attaches/reads the Result without
additional acquisition. Preparation refusals preserve zero Run admission and
zero provider I/O. Acquired cases require one source session and one row scan;
source-free cases require neither.

The complete independent nullable-parameter Program is checked and compared with
both `@p` and case-insensitive `@P` text. Existing complete predicate Programs
retain their original operand order, NULL literals and NOT wrapper. Expectations
are authored from these contracts, never obtained from compiler output.

## Focused evidence

Pinned MoonBit `0.10.12+1634b282e`, Node `22.22.0`:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/predicate_contract_boundary_test.mbt \
  src/query_program/between_parameter_boundary_test.mbt \
  src/query_expression/in_unnest_test.mbt \
  src/execution_relation/expression_between_wbtest.mbt
node scripts/local-checks.mjs test node -- \
  scripts/between-source-input.test.mjs \
  scripts/ifnull-source-input.test.mjs \
  scripts/compilation-manifests.test.mjs
```

JS **9/9**, Node **10/10**. Evidence, under
`worktrees/actql-frontend-qualify-group-aggregate-slots`:
`_build/local-checks/attempts/run-An3iBO` /
`_build/focused-evidence/focused-test-VRdO7L` and
`_build/local-checks/attempts/run-t840Py` /
`_build/focused-evidence/focused-test-pops08`.
The initial sandbox guard refusal (`Cannot inspect owned process group with ps`)
ran no tests; the subsequent bounded invocation above completed successfully.

## Public acceptance and remaining coverage

At this source commit, fresh five-package Local/HTTPS acceptance has not yet run.
The PR report will record its exact clean source SHA, manifest, tarball digests,
receipt and results. Source and common JS success do not prove this public path.
No full Core, Wasm/native execution, proof/performance campaign or manual CI
rerun is requested. Draft CI and required checks remain distinct from local
execution evidence. No merge is performed.

The general IN UNNEST audit found no new Frontend omission: parameters already
lower correctly, while field/conditional operands hit the common syntax's
literal-or-parameter `InRight` restriction. SAFE_DIVIDE likewise cannot be wired
by a spelling alias: common `safe_div` has no executable lowering, and its
zero-divisor rule alone is not the GoogleSQL error-to-NULL contract. Those
boundaries remain separate from this completed BETWEEN connection.
