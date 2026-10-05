# IFNULL source connection

Base: `eb74d7b65d0f338ef5862a7d9cd7397744a08eaa` (main). Owner: B.
Scope: public SQL/Pipe expressions to the existing common `coalesce` operation.

## Contract and counterexample

[GoogleSQL IFNULL](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions#ifnull)
is the two-argument COALESCE conditional: only SQL NULL selects fallback, and
a non-NULL first value skips runtime evaluation of fallback. This connection
uses the existing common signatures and demand evaluation. It adds neither
implicit coercions nor a new evaluator. Untyped `IFNULL(NULL, NULL)` still
has the common `NullTypeUnresolved` coverage gap; explicit supported casts
provide a typed nullable result. Wider GoogleSQL type/coercion support remains
separate. These are implementation gaps, not new restrictions on GoogleSQL.

Before the fix, `SELECT IFNULL(NULL, 7) AS value` failed compilation while the
independently authored complete Program using `coalesce` passed the normal
checker. The selected test failed at generated-Program compilation (0/1);
source inspection identifies the missing scalar-call mapping to
`UnsupportedFunction`. Evidence: `_build/local-checks/attempts/run-PzXwdr`.
This is a real compiler/checker counterexample, not a pre-fix public Run test.

`query_expression.scalar_call` now maps IFNULL to exactly two coalesce operands.
No expression is expanded or evaluated in the Frontend. Static checking still
rejects invalid names, arity, parameter declarations and incompatible types
even inside a runtime-skipped fallback.

## Independent acceptance

- A complete source-free Program expectation is authored in
  `src/query_program/ifnull_test.mbt`; expression expectations retain field and
  parameter references and both operands exactly once.
- `scripts/fixtures/ifnull-source-input.mjs` contains an independent JSON
  control and eight normal cases in total: NULL fallback, skipped division and
  cast failures, FALSE/empty STRING, typed all-NULL, Pipe continuation, empty
  Result and nullable parameter. Rows, column order and nullable contracts are
  hand-authored. The existing runner reads Result.describe, reattaches and
  resends the same request without additional admission or provider I/O.
- Six static refusals require zero admission/provider I/O. A demanded failing
  fallback requires a failed Run and no readable/describable Named Result.
- All cases are registered in the ordinary packed corpus. `--ifnull-only`
  selects only this group for Local and HTTPS, excluding unrelated campaigns.

## Pin integration and ownership

Query rules bind the grammar manifest, so the new normative paragraph changes
compilation/Run identity even for an unchanged machine Values Program. The
manifest, document import metadata and generated canonical vectors are
regenerated from their sources. Unit/Result/Program expected identities use
the independent current common-body preimages already prepared by B for #477;
historical vectors retain their original grammar, AoA and dependency closure.
The new grammar CID is
`sha256:a421b76ba7ecd9fcdf5a237643d1af26d9c0bd58075892c61a0e86840891c6e5`.
The independently derived fixed Values Run CID is
`sha256:7f758c489ad5ab297eebaf2615449d163352e7fa8cf69fac14ed3c2b9595bce9`.
These are not copied from an issuer or public Result. Pin-only integration can
be shared with dot; this PR does not alter common law bodies.

The existing packed profile test's positional assumption also fails on main's
grouped-IN prefix. This adopts B's already prepared branch-boundary assertion,
preserving every analytic corpus/profile/state check; it changes no product
route, ceiling or expectation.

D's cancellation/Model-original-wire work, H's Effect identity/hooks/cleanup,
and A's expression progress/holding/work are unchanged. Public acceptance uses
their existing Owners; success is not evidence for those separate fixes.

## Verification status

Focused working-tree checks: IFNULL expression 2/2 and checked Program 1/1;
Node registration/profile/manifest/preimage checks 20/20. Read-only compilation
manifest, document metadata, specification-family and canonical-vector checks
pass. Final clean-SHA package/digest and Local/HTTPS evidence belong in the PR
body and external evidence report. They are not asserted by this preparatory
record. Full Core, Wasm/Native execution, full packed corpus, CI and Google
service differential execution have not been run for this unit.

The first clean-SHA packed attempt (`468580ee...`, `run-9MkQjX`,
`public-query-evidence-DwEwW7`) passed the Local JSON control, NULL fallback
and skipped division/cast failures, then stopped on a missing STRING bound in
the fixture. Local's remaining cases and HTTPS were not reached. The fixture
is corrected from [the common type join](../spec/language.md#value-contracts):
literal UTF-8 bounds are 0 for the empty string and 8 for ASCII `fallback`;
coalesce retains their least restrictive common upper bound, 8. This corrects
the independent full contract expectation without changing expected rows,
product code, nullable rules, limits or ownership. Old failure evidence remains
distinct from subsequent acceptance.
