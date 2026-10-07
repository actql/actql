# Checked ARRAY expressions in UNNEST output scope

This unit connects source-free UNNEST output expansion to the existing common
expression checker. It does not introduce another type system, execution owner,
array evaluator, compatibility wire or parameter-value sampling.

## Counterexample and change

The ordinary checker accepts the complete independent finite ARRAY Program in
`src/query_program/array_constructor_test.mbt`. Explicitly selecting `element`
and `position` already lowers to that Program. The equivalent source

```sql
SELECT * FROM UNNEST([2, 1, 2]) element
WITH OFFSET position ORDER BY position
```

was rejected because output expansion inspected only parameter/property syntax.
On the integrated main baseline `219aae945f5cfd916884ca906349c9466d34a78a`
with the #870 parent, the new star variant failed after the independent Program
passed ordinary checking: `run-qSxAQr`, `focused-test-Mx2eKP`, 0/1.
Evidence is retained below this worktree's `_build/local-checks/attempts` and
`_build/focused-evidence`; this is a compiler counterexample, not a public Run
failure claim.

`unnest_source_element` now lowers the source-free expression through the usual
query-expression lowerer and reads the ARRAY element contract from
`expression_typing.check`. Construction, node, depth, text and work limits are
passed from the existing frontend limits. Budget exhaustion remains a typed
expression work-limit diagnostic. Unknown/unresolved/inadmissible element types
never supply a guessed star schema. Scalar qualified star retains its existing
`UnknownColumn` refusal.

The completed Program still undergoes ordinary common checking, parameter-value
validation, profile admission, planning and Host execution. This preliminary
scope lookup does not discharge their obligations. Object field expansion uses
existing common property expressions, including nullable receivers; offsets,
field order and hidden-slot removal retain the current value-table contract.
The checked scope applies equally to explicit projections and star, preventing
computed object ARRAYs from becoming a separate frontend representation.

## Independent obligations

- Literal `[2,1,2]`: retain duplicates and explicit offset order, with numeric
  element and offset columns.
- `ARRAY<STRING>[]`: no rows but a non-NULL string element contract.
- `IF(TRUE, [], ['x'])`: contextual element type without evaluating rows to infer it.
- `ARRAY<BOOL>[NULL]`: one NULL row and a nullable boolean element contract.
- `IF(TRUE,@items,@items)` over nullable closed-object elements: ordinary
  conditional/parameter/property operations, canonical field order, duplicate
  rows, NULL property propagation and unchanged schema on empty/NULL input.
- Untyped empty/NULL-only ARRAYs, heterogeneous items, incompatible declarations
  and scalar qualified stars: typed refusal before Run admission/provider I/O.

Complete MoonBit expected Programs and separately authored public JSON controls
are independent of compiler output. The public cases are registered in the
ordinary UNNEST corpus as well as the narrow
`--unnest-checked-array-only` consumer. The existing Local/HTTPS application
checks Named Result rows, describe contracts and column order, request reuse,
reattach/reread without repeated acquisition, and pre-admission refusal counters.

## Identity and verification boundary

The normative query rules participate in the existing grammar manifest. Normal
generators update compilation manifests, specification references and canonical
vectors; machine ARRAY/IF/UNNEST and scalar/value contracts are unchanged.
The new grammar manifest is
`sha256:865d1183ed31a4fe8b1be4e685563b932b6bc65580ed7968f8883ddc82003722`.
The independently assembled normal Values Run preimage changes to
`sha256:561ebef800dd3c16dbd971fe4c709ebf78678133926ec110d6a60714ae04e9ba`.
The #870 predecessor grammar/Run vector is retained under its original pins;
old Runs are not rebound to the new closure.

Focused JS UNNEST caller tests: 14/14 (`run-ydNneK`,
`focused-test-W1eb5s`). Targeted public-fixture and independent manifest/Run-vector
Node tests: 18/18 (`run-Xco55n`, `focused-test-F0kSwd`). Read-only compilation
manifest/document metadata checks pass; canonical checking verifies 375 vectors.
The earlier 12/13 selection reflected an incorrect new test expectation for
scalar qualified star; it was corrected to the existing `UnknownColumn` contract,
without changing product refusal behavior.

Fresh exact-SHA packed Local/HTTPS acceptance is pending at this commit. The PR
body will record its producer revision, all five package digests, evidence and
outcomes after normal packing. These focused checks do not establish full Core,
Wasm/Native, mandatory CI, correlated UNNEST, ordered GoogleSQL STRUCT support or
an expanded common ARRAY capability profile.

## First fresh public attempt

The exact `a51ebdf215a27d661a310834a7fa7a606c4c40ac` normal five-package
producer completed. README Local/reconnect/HTTPS and the first five Local ARRAY
cases passed. Case six stopped on the contextual-empty fixture's omitted
`max_utf8_bytes: 1`, not on product execution or rows. An admitted literal `x`
has one UTF-8 byte; the common IF element contract retains that bound when its
other ARRAY branch is empty (`expression_typing/signatures.mbt`, and the
independent string-literal/empty-context examples in its fixed corpus).

The fixture now authors that complete contract and adds an independent JSON
IF/ARRAY control for the same empty schema. Product typing, source expression,
expected rows, limits and refusal checks are unchanged. The failure is retained
at `../.codex-scratch/public-query-evidence-bECuPt/010.stderr.log`; this attempt
does not prove later cases or the new corpus's HTTPS route. Fresh normal packing
and acceptance will use the corrected commit, not a relabeled manifest.
