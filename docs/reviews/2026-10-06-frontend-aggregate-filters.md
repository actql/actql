# Aggregate-local WHERE Frontend connection

Base: `9b8d86efbdff7c38488c935c43a6912750cf3cc2`. Target: main.
No unmerged dependency; no shared execution Owner is changed.

## Existing contract and concrete gap

The selected GoogleSQL language checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`. Its
[aggregate calls](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/aggregate-function-calls.md)
and [functions](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/aggregate_functions.md)
allow aggregate-local WHERE. This pins a language contract, not universal
BigQuery service availability. ActQL already has the corresponding aggregate
`filter`: boolean typing, TRUE-only contribution, filter-before-argument demand,
then NULL exclusion, DISTINCT and fold. The parser previously required the
closing parenthesis immediately after the ordinary argument/modifiers.

Counterexample: `SELECT COUNT(* WHERE TRUE) AS n, SUM(1 / 0 WHERE FALSE) AS total`.
The independent complete Program uses two separate filters and the ordinary
sum/divide expression; the frontend must not turn these into a global WHERE or
hoist division into an unconditional derive. Expected public row is
`[{"n":1,"total":null}]`, number/nonnullable then number/nullable.

An initial test setup incorrectly assumed the normal checker never requests
input proofs for a general source-free Group. That assumption was removed;
`NeedsInputs` is preserved for the existing Host to close, not reported as a
ready execution. With the independent Program validated through normal checking,
the actual pre-fix counterexample failed at parse: 0/1, guard `run-elqKru`,
evidence `focused-test-5cBHak`. The earlier setup failure is `run-g8VqNC`,
`focused-test-k83zYS`; it is not the parser counterexample.

## Change

`AggregateCall.filter` retains the authored expression. The existing
`lower_aggregate_resolved` appends it through the ordinary expression owner
and the input/range resolver used by the aggregate argument. Group and existing
frame aggregates share this function. No checker, evaluation kernel, capacity
ceiling, acquisition or Result owner is replaced.

The special unfiltered global DISTINCT ARRAY_AGG key projection remains limited
to calls without a filter. Otherwise it could drop a non-argument predicate
column before the aggregate sees it. A second complete independent Program
uses an admitted id key and a predicate on amount to fix this obligation; the
frontend must not invent a key or drop the filter. Public ordered-array coverage
uses explicit ASSERT UNIQUE and a finite LIMIT through existing owners.

## Scoped verification

- First repaired counterexample plus existing query parser callers: JS 18/18,
  `run-qAoxUm`, `focused-test-8ZPzwh`.
- New predicate AST/malformed syntax and input/sibling-alias scope checks:
  JS 4/4, `run-MAUsuq`, `focused-test-g5BgkR`.
- Final complete Group Programs, source-free callers, new parser checks and
  actual Values Run issuer: JS 11/11, `run-DmrEUu`, `focused-test-6ZiC3i`.
- Node fixture/normal-corpus registration and independent grammar/Run vectors:
  5/5, `run-Jby4A6`, `focused-test-4VjzXB`.
- `moon info src/query_syntax` regenerates the changed public AST interface.
- Read-only compilation manifest, document metadata, canonical JSON and
  spec-family checks pass. Conformance remains false.

Focused commands use `node scripts/local-checks.mjs test moon -- --target js`
with the listed exact files, or `test node --` with the three related test files.
No full Core, Wasm/Native, proof campaign or manual CI rerun is performed.

The normal packed corpus and `--aggregate-filter-only` selection contain an
independent JSON control and 9 source successes: independent aggregate/query
filters, DISTINCT/duplicate/NULL behavior, empty global Result, nullable parameter,
filter-gated failing argument, qualified input, retained pre-SET alias value,
analytic caller, and ordered keyed array. Five preparation refusals fix type,
missing/undeclared name, sibling alias and removed range failures. A TRUE-filter
failing argument must terminate without successful Result publication. Exact
fresh-package execution evidence is recorded after the clean-HEAD public run.

## Identity and remaining boundaries

Normative query rules and grammar bytes change the grammar manifest and its
Run dependencies. Machine aggregate shape, common laws and registry are unchanged.
The independent normative-preimage calculation gives grammar
`sha256:8ccb3fc5856a12a6f195f60959e446ff0c46bd67cee78c5065b344cc5d2f5446`
and Values Run
`sha256:d60f040f1285fd7f1e792c0b70da904e0c906d6549fcd53caa305f6cfda82c08`.
The complete preceding main grammar body and Run vector remain immutable tests.

This does not widen COUNTIF DISTINCT (currently rejected by its common contract),
MIN/MAX DISTINCT, arbitrary aggregate HAVING/LIMIT, or aggregate calls nested
inside scalar expressions. Pending aggregate-expression PRs retain their own
scope. Ordinary common key, order, domain and capacity requirements continue to
apply. Other frontend and common-runtime gaps remain separate work units.
