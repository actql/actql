# Scalar source, contract and execution boundaries

Date: 2026-10-08. Inspected main: `a5df611da50e2d652a860359cc50d04c170c1a2d`.
This is a focused common-owner handoff. It does not establish public runtime
acceptance, propose another evaluator, or complete the Frontend migration.

## Independent source-to-Program controls

The [input and expected result fixture](fixtures/scalar-boundary-input.json)
contains complete SQL queries, independently authored JSON Programs, and expected
rows and columns. The result expectations were not produced by executing ActQL.
The `scalar_contract_boundary_test.mbt` test separately compares complete source
lowering with manually authored Programs and checks both using the ordinary
Program checker. These checks prove wiring and type admission, not execution.

| Source | Common expression | Expected value | First observed common execution-lowering result |
| --- | --- | --- | --- |
| `SELECT SQRT(9) AS value` | `sqrt(literal(9))` | `3` | `ExpressionNotImplemented("sqrt")` |
| `SELECT LOWER('É') AS value` | `lower(literal('É'))` | `é` | `ExpressionNotImplemented("lower")` |
| `SELECT UPPER('é') AS value` | `upper(literal('é'))` | `É` | `ExpressionNotImplemented("upper")` |
| `SELECT TRIM('\u2003value\u2003') AS value` | `trim(literal(U+2003 + "value" + U+2003))` | `value` | `ExpressionNotImplemented("trim")` |

Frontend `query_expression/lower.mbt::scalar_call` preserves these operations and
operands. `expression_typing/signatures.mbt` admits their operand/result domains.
The independently checked expressions then reach
`lowering_relation/expression.mbt::expression_tag`, which lacks these four
operations and rejects them before constructing an executable expression.
This is not an alias, source-decoding, or text-to-Program rewrite failure.
Changing Frontend spelling cannot supply the missing common execution support.

## TRIM also has a normative alignment gap

The selected GoogleSQL checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`; its `docs/string_functions.md#trim`
and the [official TRIM reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#trim)
define Unicode codepoint trimming. With no second argument, whitespace is removed
at both ends. The U+2003 control distinguishes this from ASCII-only trimming.

The current `spec/dependencies/aoa-rela-scalar-laws.json` instead declares
`unicode.trim: "ascii-whitespace"`. Implementing that pinned law unchanged would
still not align the public `TRIM` spelling with the adopted GoogleSQL STRING
meaning. This conflict is demonstrated by contract inspection; it is **not** a
claim that ActQL returned the wrong public row in the current runtime, which
rejects execution earlier. The optional character-set argument and BYTES
overload are separate unconnected coverage. Neither is silently implemented by
the current one-argument mapping.

LOWER/UPPER must likewise use the selected Unicode rules for STRING; an ASCII
implementation or implicit NFC normalization is not an acceptable replacement.
The [official STRING reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#lower)
and selected checkout distinguish STRING behavior from ASCII-only BYTES case
conversion. These controls preserve the original decoded operand values.

## Reproduction and observed scope

Toolchain: repository MoonBit `0.10.12+1634b282e`; Node `22.22.0`. Both commands
used the existing bounded/nonzero-test wrapper on JS. They ran on the inspected
main with the added test sources, before this evidence commit; they are not
clean submitted-SHA or CI evidence.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js src/query_program --filter 'scalar boundary source*'
```

Result: 1/1; the test covers all four SQL/JSON pairs and both checker inputs.
Evidence: `_build/local-checks/attempts/run-jyTHqH` and
`_build/focused-evidence/focused-test-yK8xFg` in the B-owned
`worktrees/actql-frontend-scalar-contract-boundaries` checkout.

The [saved diagnostic](fixtures/scalar-boundary-diagnostic.mbt) uses the existing
`lowering_relation` test helpers. Copy it to an unused test filename in that
package, run the command below, and remove only that copied file after the
command is terminal. It prints implementation availability instead of fixing
today's missing operations as permanent negative expectations.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- \
  --target js src/lowering_relation --filter 'scalar boundary diagnostic*'
```

Observed: all four emit `ExpressionNotImplemented` with their exact operation
name. The one diagnostic test completed; its completion is not successful
execution of the scalar functions. Evidence:
`_build/local-checks/attempts/run-qNdDE0` and
`_build/focused-evidence/focused-test-oxQlPv`. The diagnostic copy was removed
from `src` and retained here. No all-Core, Wasm/native, packed campaign, provider
I/O, external service differential test, or CI rerun was performed.

## Ownership and completion requirements

Common execution belongs to A. The minimum missing boundary is the existing
typed-expression lowering and expression-frame evaluation for these operations;
preserve the one common Owner, bounded progress, NULL propagation, demand masks,
operand retention and cleanup. The TRIM rule requires its normative owner and
dependent law/CID/schema/vector closure as well as execution code. Coordinate
that contract change with dot; do not retain the old CID for changed semantics.
No current A worktree was edited, and no Frontend substitute or compatibility
fallback was added.

B retains the source and independent JSON controls. After the common owner
provides an executable fixed SHA, run both controls through the existing packed
Local/HTTPS application, compare rows and described contracts, and confirm empty
results, nullable operands, Unicode/line endings, demanded errors and lazy
branches. Existing count/limit/order and request-reuse checks remain in force.
Until then, source/checker success and the missing execution coverage stay
separate. Other independent Frontend work can continue.
