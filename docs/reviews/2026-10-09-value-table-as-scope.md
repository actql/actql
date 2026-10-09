# Pipe AS preserves value-table kind and whole-column scope

This is a Frontend repair, not a new execution owner or a complete GoogleSQL
value-table implementation. The branch normally integrates main
`1f0c7edb49dac517cfd451f1686aa2df79fb0c53` at
`69ae5ef67f8e2934e1dc69b0d5c744e97bb713af`. Its unmerged parent is PR #1155,
with PR #1152 beneath it. The final merge destination remains main.

## Counterexamples and reference

These sources were refused before the repair, despite independently authored
ordinary Programs passing the common checker:

```aql
FROM UNNEST(@items) element
|> AS current
|> WHERE current > 0
|> SELECT current AS value
|> ORDER BY value
```

```aql
FROM UNNEST(@items) element
|> AS current
|> SELECT current AS original, id
|> ORDER BY id NULLS LAST
```

```aql
FROM UNNEST(@items) element WITH OFFSET position
|> AS current
|> SELECT current.element AS original, position
|> ORDER BY position
```

The selected GoogleSQL source is
`d82db99a923a46571f543a13899dc791a7b6f743`. `ResolvePipeAs` and
`UpdateNameListForTableAlias` preserve a single value table and replace its
range name. An ordinary multi-column table instead flattens former value-table
ranges to current whole columns. `pipe_as.test` includes scalar UNNEST and
object/proto examples. Its multi-column field-lookup TODO explicitly records
an implementation inconsistency; it is not adopted as a language restriction.
This is source inspection, not live Google service differential execution.

For scalar input `[2,null,1]`, the first query yields values `1,2`. For object
input `[{id:2,label:'z'},null,{id:1,label:'a'}]`, the second query yields the
original objects with IDs `1,2,NULL`, and the third preserves offsets `0,1,2`.
Whole NULL objects remain distinct from non-NULL objects with NULL properties.

Pre-repair evidence: `run-aD6yXn` / `focused-test-wN4bVD`, exit 2, **0/3**.
The expected Programs passed their checker assertions; text compilation failed
before the equality comparisons. There was no pre-repair public execution.

## Repair

Private row scope now retains value-table kind, actual whole-column/member
ownership, and captured qualified-star layouts. AS changes bindings without
adding a derive, acquisition, task, or storage boundary. A single value table
keeps its new whole receiver; an ordinary row exposes former ranges as whole
current columns. Star still expands admitted members rather than publishing
an additional whole-object column.

SET, DROP and RENAME use actual columns as targets, not implicit object
members. Surviving range bindings and their star layouts retain pre-edit slots.
JOIN remaps these snapshots through existing output ports. SELECT/GROUP/INFER/
NEAREST continue to create their own output scopes. AS cannot bypass the
existing unsupported closed-value-table DISTINCT boundary.

`docs/spec/query-text.md` corrects its previous blanket assertion that AS
creates an ordinary output scope. Existing generators update compilation and
normative pins and canonical identity vectors. No common value law, Program
operation, evaluator, checker, provider or execution owner is replaced.

The grammar manifest changes from
`sha256:c4364e9947c8d6c7538d9245fca2da3fc0cd44bd70caceff58862ba9629c90d6`
to `sha256:f57132973b7e2bca2462607971e6ef8ab3529e3bf18b295f723a185120163e44`.
The independently reconstructed fixed Values Run changes from
`sha256:71a90eff92faeb07d1efe6c8bbe56bdcaac3d87a04b6a6c2f3e314a52503e069`
to `sha256:fa57a9c0f667cae5597a30f9cf4606c86d3c15620526d757f7942e16129b01bf`.
Its Values Unit and Result Plan remain unchanged. The complete old grammar and
Run preimages are retained in `scripts/fixtures/pre-value-table-as-grammar.json`;
old stored Runs are not rebound to current identities.

## Focused verification

All commands use the pinned Node and MoonBit toolchains and bounded,
nonzero-test wrappers.

- Related JS callers: **70/70**, `run-hK71HK` / `focused-test-p3kehL`.
  Selection includes AS, ordinals, scalar receiver precedence, whole-column
  edits, OFFSET/range targets, JOIN continuation, STRUCT stars, GROUP stars,
  analytic output scopes, Pipe scope and star replacement.
- Final AS edit counterexamples and Values Run material identity: **11/11**,
  `run-pmgAJu` / `focused-test-LXu8CM`.
- Initial selected Node check: **39 passed**, one stale generated canonical
  manifest fixture and one malformed new fixture module failed. Both were
  corrected; neither was a product execution result. The earlier JS repair
  run `run-YDYq1h` / `focused-test-AwdMCc` was **47/49** because two independent
  expected Programs incorrectly reserved an OFFSET name when OFFSET was absent.
  The expected allocator layouts were corrected, not the product allocation.
- Changed Node fixtures and canonical manifest checks: **17/17**,
  `run-3xYmUQ` / `focused-test-5B59RB`. The preceding Node run also passed
  independent Values vectors, SGA pin reconstruction, frontend profile,
  document validation and normative imports without later source changes.
- Read-only compilation manifest, document metadata, canonical-vector and
  spec-family checks are selected rather than the complete spec gate.
  Canonical generation/check verifies 382 independently authored identities;
  spec-family validation reports `conformance:false`, not runtime completion.

Public fixtures add eighteen positives, including two independent JSON
controls, and three precise refusals to the existing ordinary and narrow
packed consumer. They cover repeated/quoted AS, whole values, member collision,
qualified/unqualified star, immutable star after SET, RENAME, DROP, JOIN
remapping, empty object values and typed empty/NULL arrays. The prior pure-AS
old-range refusal remains valid and is retained. Refusals require the existing
typed code, zero durable Run admission and zero Source I/O.

## Public acceptance and remaining coverage

Fresh normal five-package production and external Local/HTTPS acceptance are
pending at this checkpoint. The new corpus is 129 positives / 52 refusal loops
per transport. Rows, Result.describe contracts/nullability/column order,
stream completion, private-column absence and same-Run replay without extra
acquisition/execution remain required; fixture construction is not execution.

Full Core, all-target execution, complete packed suites, hosted artifact
transport, performance and final required CI are not claimed. Exact submitted
HEAD CI will be inspected after publication. This unit does not complete the
broader Frontend goal or unresolved common contracts for ordered STRUCT values.
