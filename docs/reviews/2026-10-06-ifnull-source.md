# IFNULL source connection

## Current-main integration review

Normally integrate `7df035b21079379ca5bcdccaf45adb1b2091cd1e` into the
preserved IFNULL branch. Resolve the eleven conflict paths by retaining both
normative paragraphs and all IFNULL, HAVING, COUNTIF and frame public selections.
The metadata and current compiler pins are generated from the combined bodies;
the complete grammar document import introduced by #495 is preserved.

The independent Run vector retains main's pre-membership and current vectors,
plus the earlier IFNULL and Graph-difference source closures. The combined
grammar manifest is `sha256:c7db9149ce04b3f85a273f97b5e4b1647e62e352484fb56309f5a347744fe37b`;
the independently assembled current Run is
`sha256:2624f666695d785e72040453976d086dc98e7778ac5dfeb5a75ba93cc8f67891`.
Neither expected identity comes from the product issuer. The narrow COUNTIF
registration guard now checks membership in the selector rather than requiring
its flag to be first; every corpus and isolation obligation remains checked.

Focused integration attempt `run-a9V8oZ` passed IFNULL 3/3, the Run consumer
1/1, and Node fixture/profile/independent preimage tests 23/23. Read-only
compilation metadata, document imports, specification-family and 370 canonical
identities passed. Its first attempt (`run-CK7VAV`) found two stale assertions
and is retained separately. The old public success at `45bccfa...` is still
evidence for that exact SHA, not for the integration. Current clean-SHA
publication, actual history and narrow public results follow in the PR.

The #463 integration remains a separate common-law unit: this merge does not
adopt typed-JSON changes or overwrite its branch. Its current pins must be
generated from its own combined law/body after integration, while preserving
both historical generations. No shared work/holding or Effect meaning changes
are made here.

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
