# Literal ARRAY membership: source-to-Program connection

Baseline: main `d2b1f0bec03649eb84b6352221a7378e489f4b84`.
This unit is independent of the pending finite Graph quantifier and SGA ledger
PRs. It changes Frontend lowering, not the common execution owner or scalar laws.

## Missing connection and independent controls

`SELECT 2 IN UNNEST([1, 2, NULL, @p]) AS included` parsed, but the lowerer
emitted an ordinary `array` node for the right operand. Common expression
admission permits a membership literal list or array parameter there, so it
rejected the generated expression. The existing `IN (1, 2, NULL, @p)` spelling
already has the required common representation.

The independent control is `{"in":[{"literal":2},{"literal":[1,2,null,{"$param":"p"}]}]}`.
The complete Program control is authored separately in
`src/query_program/in_unnest_literal_array_test.mbt`; no compiler output is used
to construct its expressions, declarations, fields or Named Result. Both source
variants and that control pass the normal checker with the declared parameter.

Before the fix, the new expression regression failed at common expression
admission: 1/2 tests passed in `_build/local-checks/attempts/run-94lnoH` and
`_build/focused-evidence/focused-test-LmHN10`. This is a compile-boundary failure,
not evidence of an accepted Run failing publicly.

## Selected meaning and bounded lowering

The [GoogleSQL IN operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#in_operator)
defines empty-set, matching-value and NULL behavior. The
[array scanning examples](https://docs.cloud.google.com/bigquery/docs/arrays#scanning_arrays)
include literal arrays in IN UNNEST. These are the reference for the hand-authored
Program and truth-table controls, not a live differential run against BigQuery.

Unannotated `[...]` and `ARRAY[...]` with scalar literal atoms and immediate
scalar parameter holes lower to the existing membership literal list. Grouping
and signed numeric atoms retain their existing interpretation. Item order,
duplicates and NULLs remain present. The common checker owns type, parameter and
NULL rules; the common expression engine executes membership.

Each additional grouping/item inspection consumes existing expression work.
The lowerer does not evaluate general elements, substitute parameter values,
erase type annotations or add an execution owner. General expressions such as
`[1 + 1]` and annotated arrays keep their ordinary common admission and current
unsupported status. This is a coverage gap, not a GoogleSQL language restriction.
Ordinary SELECT ARRAY and membership array parameters keep their existing forms.

## Identity and generation

The existing compilation manifest generator updates the query-rules hash and
grammar manifest. Current grammar CID:
`sha256:2fca45d69a94d9d91a6903f72007bccb09bf2c945cfca7187d61808222eac60f`.
No common expression law, value contract or registry meaning changes.

The independent Values Run vector rehashes the complete normative preimage.
Its current Run CID is
`sha256:1e580903177ae141bc703bead4e9164bd200f4d60e7cde63d89dd04ea5be3bf6`.
The Values Unit, cardinality proof and Result Plan stay unchanged. The preceding
ARRAY grammar closure and its Run vector remain frozen separately; no saved Run
is relabeled under the new grammar identity.

## Executed checks and pending public acceptance

Pinned Node 22.23.2 and MoonBit 0.10.12+1634b282e were used.

- Expression regressions and affected IN-list callers: JS 7/7,
  `run-49cWl7`, `focused-test-FXKT1N`.
- Complete Program controls and existing array-parameter callers: JS 4/4,
  `run-Zgdv6e`, `focused-test-4W3uSl`.
- Independent fixtures, ordinary ARRAY registration and Run vectors: Node 8/8,
  `run-b9fuP2`, `focused-test-jN5yIx`.
- Affected Values Run material boundary: JS 1/1,
  `run-vykE2I`, `focused-test-6UUDSh`.
- `node scripts/compilation-manifests.mjs` and changed-source formatting pass.

The normal packed corpus includes ten positive cases and seven pre-admission
refusals. The positive cases cover an independent JSON control, match-before-NULL,
unknown results, empty sets with nullable left values, ordinary ARRAY coexistence,
empty rows, parameter holes, Pipe projection, and a one-acquisition WHERE with
duplicate output rows. Rejections cover general elements, retained annotations,
mixed types, undeclared/wrong parameters and invalid numeric atoms.

Public acceptance must use normal five-package packing from the clean committed
source, followed by `node scripts/test-packed-public-query.mjs
--in-unnest-literal-array-only --keep-artifacts` for Local and HTTPS. The existing
driver compares Named Result values, declared column order/type/nullability,
hidden-column absence and acquisition counters; same-request retry, attach and
reread must not acquire again. Rejection must precede Run admission and provider
I/O. At this commit, this fresh packed run and submitted-HEAD CI are pending.
No older client-wire API, compatibility export or fallback is introduced.

General membership ARRAY expressions, untyped NULL-only/default-empty type
inference and additional ARRAY annotation types remain tracked coverage gaps.
This unit does not claim the entire Frontend or all backends conform to GoogleSQL.
