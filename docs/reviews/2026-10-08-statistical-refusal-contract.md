# Statistical aggregate public refusal contract

Base main: `e6b224fc96eb1930c7bcdc783ea8e80ab9c36a44`.

The complete statistical-aggregate public corpus still treated
`SELECT VAR_POP(amount) OVER (ORDER BY id) AS v FROM records` as an ordinary
invalid-input refusal. The public helper now requires an explicit expectation
for an implementation limit; that distinction must not be weakened globally.

The implemented profile in `docs/spec/query-text.md` explicitly excludes
default analytic frames. `statistical_aggregate_test.mbt` independently requires
`UnsupportedAnalytic` for this source form, while the ordinary checker rejects
statistical DISTINCT after lowering. These are separate failure boundaries.
GoogleSQL permits the omitted frame, with its selected default semantics; this
repair does not make that unsupported profile a permanent language restriction.
See the [GoogleSQL window specification](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/window-function-calls).

Only the default-frame public fixture now requires the exact existing
`ClientProgramImplementationLimit`. All eight submitted refusal texts and their
names remain. No source, independent JSON Program, row/type/order expectation,
acquisition count, execution bound or normal packed registration is changed.
The existing refusal consumer still checks submission lookup and zero Run
admission/Source I/O. Other invalid calls retain their ordinary refusal contract.

The new focused Node regression failed before correction: **0/1**,
`run-HUjtNB`, `focused-test-2BWblS`, because the expected code was absent.
It also retains all fourteen positive fixtures, eight refusals, one demanded
execution failure and the independently authored nullable analytic-prefix rows.
The corrected fixture and existing public refusal consumer passed **8/8 Node**,
`run-oSGFrI`, `focused-test-E7ltsK`. The exact-HEAD packed Local/HTTPS result
will be recorded in the PR and retained receipts after execution.
Syntax/checker tests alone do not establish public execution.

No parser/lowerer, execution owner, Program/type/value contract, grammar or
identity preimage changes. No generated pin update is required for this fixture
correction. This unit is independent of #988/#990 and dot's ranking-arity #992.
Default analytic frames, statistical DISTINCT, wider numeric types, nonfinite
results, Cloud and whole-Core/all-target verification remain separate coverage.
