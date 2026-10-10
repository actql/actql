# Reuse evaluated GROUP keys across not-equal operator spellings

Inspected main: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
This is an independent Frontend repair, not a common comparison change.

## Fixed counterexample

```sql
SELECT COUNT(*) + IF(pair.x != 1, 1, 0) AS n
FROM pair
GROUP BY x <> 1
```

The authored complete JSON Program computes `neq(x, 1)` once before GROUP,
groups that Boolean slot and adds COUNT to IF over the evaluated key. The
ordinary checker accepts it. The same-spelling source control also lowers
to that independent Program. On unchanged main, the mixed-spelling source
instead rejects with `Expression(UnknownReference)` after GROUP has dropped x.
Baseline: `run-O0hJUs` / `focused-test-W7ibP8`, one failing test.

The selected [GoogleSQL comparison reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#comparison_operators)
defines `!=` and `<>` as two spellings of not-equal, including ordinary NULL
propagation. The existing Frontend already emits the same common `neq` operator
for both. This repair connects reuse to that installed mapping. It does not
claim live Google differential execution, full coercion, nonfinite-number or
STRUCT comparison conformance.

## Repair boundary

The existing binary mapping is extracted into one private helper retaining
both common operator and negation polarity. Ordinary expression lowering and
the reuse identity query use that helper; no independent mapping table or
new expression operator is added. `same_expression` still compares operand
trees and resolves each receiver in its original clause scope. LIKE and NOT
LIKE, equality and not-equal, different receivers and removed ranges remain
distinct. Types, demand, keys, order, resource bounds and provider execution
remain obligations of the existing checker and runtime owners.

No grammar/spec pins or retained identity vectors change. #1198's scalar
function alias repair is separate; this branch is based directly on main and
does not treat #1198's acceptance as evidence for this revision.

## Focused verification

After repair, the affected JS tests passed **30/30**:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/query_expression/binary_operator_identity_test.mbt \
  src/query_expression/lower_test.mbt \
  src/query_program/group_comparison_alias_test.mbt \
  src/query_program/sql_grouped_subexpression_test.mbt \
  src/query_program/repeated_group_key_test.mbt \
  src/query_program/order_property_receiver_reuse_test.mbt \
  src/query_program/window_key_receiver_reuse_test.mbt
```

Evidence: `run-4jak8N` / `focused-test-Ys7MGE`. Tests compare the complete
independently authored Program, check both Programs normally, preserve exact
UnknownReference diagnostics for distinct operands and exercise ordinary
expression lowering plus GROUP/ORDER/window reuse callers.

The fixture and normal/selected public registration tests passed **20/20 Node**:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  scripts/group-comparison-source.test.mjs \
  scripts/repeated-group-key-source.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/compilation-manifests.test.mjs
```

Evidence: `run-kr1A9a` / `focused-test-qTOflQ`. The selected generated interface
was updated by pinned `moon info --target js,wasm,native src/query_expression`
through the bounded guard (`run-Xf90pJ`, exit zero). This is selected-package
interface compilation, not Wasm/native runtime execution.

## Public obligations

The normal group-ordinal corpus adds eight positives and three exact
ClientProgramInvalidInput refusals, preserving all preceding 17/6 cases.
Independent JSON control, both not-equal spellings, qualified input, repeated
key spelling, output alias collision, nullable HAVING, Pipe and empty input
retain independent Boolean/Number contracts, declared column order and rows.
False, true and NULL form separate groups; duplicate true rows contribute two
to COUNT. Source WHERE id > 0 excludes the deliberate extra input row.

The existing `--group-ordinal-only` acceptance therefore requires 25 positives
and nine pre-admission refusals on both Embedded Local and authenticated HTTPS.
It checks Named Result rows and describe contracts, hidden-column absence,
stream completion, one Source acquisition and no extra acquisition on reread,
reattach or same-request resend. Different receivers, operators and removed
ranges must refuse with zero Run admission and Source I/O. No generated
Program is repaired by the test driver.

Clean-HEAD normal five-package production, digest verification and public
acceptance are pending at this preparation commit; record their actual source
SHA and receipt separately in the PR. Hosted CI, complete Core, Wasm/native
execution, Cloud and remaining Frontend coverage are unverified. No manual
CI rerun or PR merge is performed. The common subscript gap #1195 is separate.
