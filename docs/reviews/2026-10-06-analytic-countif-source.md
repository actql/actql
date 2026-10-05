# Analytic COUNTIF source connection

Owner: B. Base main: `c577b0c7695c08b3696e52e981cef50c8f8e3023`.
Scope: the existing COUNTIF aggregate inside an explicit inline ROWS frame.

## Existing contract and counterexample

[GoogleSQL COUNTIF](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#countif)
counts TRUE values and admits an OVER clause. FALSE and NULL contribute zero;
an empty frame returns zero. ActQL's existing `count_if` aggregate signatures,
analytic checker, frame demand and Local aggregate execution implement this
contract in the supported Boolean/number domain. This change adds no type,
coercion, frame default, operator or evaluator. Existing broader GoogleSQL
coverage gaps, including implicit/default frames, remain separate.

The query parser already classifies COUNTIF as an aggregate; ordinary GROUP
lowering already maps it to `count_if`. However, `lower_analytic_call` accepts
COUNT/SUM/AVG/MIN/MAX and omits COUNTIF. On the base source the independent
Values Program passes the normal checker, while generating that Program from
SQL fails (0/1, `_build/local-checks/attempts/run-8SyrEi`). This is a compiler
counterexample, not a claim of a pre-fix public Run failure.

The fix adds COUNTIF to that existing analytic allowlist. Field and computed
arguments continue through `lower_aggregate_resolved`; frame bounds and input
scope are unchanged. SELECT output aliases are not visible to OVER arguments.
The common checker still validates Boolean arguments and parameter bindings.

## Independent acceptance

- The full independent Program in `src/query_program/analytic_countif_test.mbt`
  retains nullable Boolean input, a computed numeric predicate, both frame
  limits, output columns and explicit order. SQL and Pipe match it exactly.
- `scripts/fixtures/analytic-countif-source-input.mjs` uses input deliberately
  out of order, NULL, FALSE and duplicate TRUE-valued occurrences. Six normal
  cases cover independent JSON, SQL, LIMIT/OFFSET, Pipe following frames with
  an empty tail, nullable partitions with duplicates and a typed empty Result.
- Four static refusals cover non-Boolean input, an unsupported missing frame,
  undeclared parameters and an invented SELECT alias. They require zero Run
  admission and provider I/O. A demanded arithmetic failure must publish no
  readable or describable Named Result.
- Existing packed acceptance compares complete Result.describe contracts,
  declared column order and rows; it checks one source acquisition session and
  no extra acquisition/admission after reading, attaching or resending.
- Cases join the ordinary packed corpus. `--analytic-countif-only` is the
  focused Local/HTTPS selection and excludes unrelated campaigns.

Normative grammar already admits aggregate OVER and the selected profile names
registered OVER aggregates. No normative body, common law or CID pin is changed
by this implementation completion. Structural differences between the public
JSON control and generated source Program are permitted; their observations
remain independently fixed.

## Ownership and remaining coverage

D's Model-original-wire/cancellation, H's Effect identity/hooks/Ledger cleanup,
A's expression progress/measurement and C's Graph contracts are unchanged.
This connection uses their existing Owners and does not validate their separate
fixes. Full Core, full packed corpus, Wasm/Native execution, Cloud and live
Google-service differential execution are not local checks for this unit.
Final clean-SHA package identities and execution evidence are recorded in the
PR body and external report, separately from working-tree focused results.

A separate inspection found REPLACE missing from the Frontend function map,
but also unsupported by `lowering_relation.expression_tag` in common Local
execution. Its common expression syntax/type signature alone does not establish
public execution support. No REPLACE source acceptance or substitute evaluator
is added here; this is a recorded execution dependency, not a reproduced Run
failure or a new language restriction.
