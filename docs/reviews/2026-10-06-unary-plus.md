# Unary plus: preserve the existing numeric expression contract

The GoogleSQL [arithmetic operator profile](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#arithmetic_operators)
accepts unary plus on numeric expressions and retains the operand's numeric
type. This change connects the current ActQL number/decimal typing contract;
it does not claim support for every GoogleSQL numeric domain.

At base `b089642827e7c354195ecfec79e5e0aa3fa532b2`, the query parser accepts
`+amount` but expression lowering rejects it with `InvalidArguments`. The
pre-fix independent regression executes and fails. Literal numeric plus already
works and keeps its existing constant representation.

Nonliteral numeric plus now lowers to two existing, type-preserving `negate`
forms. There is one operand subtree, so it is evaluated once. Ordinary checker
typing rejects nonnumeric expressions and preserves decimal precision/scale and
NULLability. Removing the operator would incorrectly admit STRING/BOOL;
subtraction from a fabricated zero could change decimal typing. No new evaluator,
numeric primitive, coercion, identity rule or execution owner is introduced.

The independent complete Program test covers a decimal CAST expression and
ordinary checking. Separate type fixtures cover nullable/nonnullable number and
decimal. Public fixtures cover SQL/Pipe fields, negative and NULL parameters,
empty output, duplicate rows, lazy/demanded operands, and alias-first versus
qualified-input ORDER. The shared public harness checks rows, declared column
order/contracts, one acquisition, stable Run resend/reattach and no admission or
source I/O for preparation refusals. These cases are also in the ordinary packed
corpus, not only a local selection.

## Separate common decimal execution gap

`expression_typing/signatures.mbt` accepts `negate` on decimal and retains its
contract. `execution_relation/scalar.mbt::unary` handles number and NULL, but
rejects every captured value, including an admitted decimal. A separate direct
common-boundary probe constructs coefficient `1250`, precision 8, scale 3 and
expects negation to produce `-1250` with the same type. It executes and fails
with `InvalidOperand` on the unchanged base implementation.

The preserved probe and logs are under `review-artifacts/b-unary-plus-2026-10-06`.
Run the probe by temporarily copying `decimal-negate-probe.mbt` to
`src/execution_relation/unary_plus_probe_wbtest.mbt` and selecting only that file
through the existing bounded/nonzero JS test wrapper; remove only the diagnostic
copy after the invocation has ended. The probe is not installed as a passing
product test and its expected value is not changed to accept the defect.

This is an A common-scalar boundary handoff, not evidence of an end-to-end public
Run failure. An earlier expression probe stopped during preparation because its
existing helper has no decimal numeric profile; it did not reach scalar
execution. A preliminary diagnostic also failed to compile because Value has no
Debug implementation. Both attempts are retained separately from the valid
direct probe. B does not modify the common evaluator or claim decimal execution
completion from checker success. Decimal public acceptance remains open until
the common boundary is repaired and the same source/Program path is exercised.

## Verification scope

Focused lowering, Program, typing and public-routing tests are used locally.
Clean-revision five-package production and the existing external installation
exercise only `--unary-plus-only` through Embedded Local and HTTPS. Exact source
SHA, package digests, executed results and hosted CI state are recorded in the
PR and retained evidence. All-Core, Wasm/native, proof campaigns, performance,
Cloud and the complete packed corpus are not claimed by this unit.
