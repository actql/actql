# DISTINCT ORDER: preserve output receiver typing during selected-path reuse

## Fixed boundary and independent counterexample

This unit starts at published main
`61655a2f732592d4ad07b11f2d15aaa4edcd61ac`, after #1468 and #1469.
[source-baseline.json](source-baseline.json) records its tree and the original
helper hash. The finding is source inspection; B has not executed the old
compiler, common checker or public Run.

```sql
SELECT DISTINCT score AS original_score, -score AS payload
FROM objects AS payload
ORDER BY payload.score + 1 NULLS LAST
```

`payload` in ORDER is the evaluated numeric output alias. Applying a property
to it must reach the existing common `TypeMismatch("closed object receiver")`.
It must not resolve through the older FROM range to input `score`.

`append_distinct_order_member_expression` supplies a resolver to the shared
evaluated-subtree matcher. The original resolver checks output aliases only
when the complete path is one token, then tries the original input scope.
Consequently `payload.score` can match selected input `score` through the
old range. Binding that subtree to `original_score` replaces the invalid
property expression with a valid number and erases its required type rejection.
The earlier whole-SELECT-expression reuse check already blocks this receiver
collision; this separate selected-subtree path did not.

The independent complete invalid Program retains ordinary numeric projection
and DISTINCT, followed by the authored property on output `payload`. The valid
control changes ORDER to `original.score + 1` with a nonshadowed FROM range.
For input `10,20,10,NULL`, that valid control publishes three rows, keys
`10,20,NULL`; ordering by numeric output `payload` instead yields `20,10,NULL`.
Both preserve nullable number columns in declared order and omit the sort helper.

## Minimal correction

Only `query_order_selected_members.mbt` changes product behavior. When a
multi-part path starts with an output alias, whole input-range lookup is blocked
before proving selected-subtree identity. Existing prefix lookup sees the output
receiver; existing expression lowering keeps the property operation and the
common checker owns its rejection. No new type system, cast, comparison,
evaluator, DISTINCT contract, acquisition path or compatibility fallback is added.
Nonshadowed qualified input paths continue to reuse their selected value.

This applies the adopted ORDER receiver and alias rules in
[query text](../../docs/spec/query-text.md). It uses the same boundary already
present in `reusable_order_expression` and `order_expression_slot`. This is a
separate call site from GROUP ORDER #1474 and has no unmerged dependency on it.
The queued DATA redesign and submitted #1471/#1474 heads are untouched.

## Authored verification and public declarations

- Two MoonBit tests compare complete independently authored Programs and exact
  common rejection kind, including dotted, explicit-object and quoted receiver
  spellings. The invalid Program itself must first reject for the intended type
  reason. The qualified-input control must pass the usual checker.
- Two Node tests pin independent JSON controls, opposite numeric output order,
  nullable ordered columns, Source count, refusals and normal/narrow registration.
- The ordinary packed corpus includes five normal and five refusal declarations.
  The existing driver also selects only those declarations with
  `--distinct-order-receiver-only`, per Local/HTTPS transport. JSON control and
  authored DATA/text use the same Source/checker/Host. Neither the test nor the
  driver repairs a lowered Program.
- Missing type permission is an admission refusal: existing refusal-before-I/O,
  same-request, Source acquisition, complete ordered schema, hidden-column and
  cleanup assertions are retained. Existing five packages and producer/public
  300-second limits remain unchanged; no shared Heavy window is reserved.

These are authored tests and declarations, not executed runtime counts. Property
member spelling stays `score`; quoted receiver case tests alias lookup without
claiming an unrelated common object-member case extension. The object DISTINCT
`NotKeyComparable` limitation remains a separate existing owner boundary.

## Evidence and remaining work

[prepared-checks.json](prepared-checks.json) gives existing bounded-wrapper
commands for Root's independent worktree. B does not retry the retained guard
rejection or bypass it with raw test execution. Individual formatter/syntax,
read-only freshness, independent registration enumeration and whitespace results
are recorded separately from compiler/runtime/public execution.

The initial source inventory is retained in
[baseline-public-inventory.json](baseline-public-inventory.json). The combined
registered inventory has 3,957 declarations: 2,488 normal, 50 execution-failure,
1,419 refusal; digest
`204ec88bff08633a681e3c284e17810aa2517ff3be41c8bf24ffd4863c9db6a3`.
It is enumerated from authored registration data, not from product results.
No grammar or owned contract body changes, so upstream identities and historical
preimages are preserved without inventing new pins for this source fix.

Compile, nonzero regression execution, pristine public Local/HTTPS, actual
rows/schema/refusals/counters, cross-target execution and CI remain unverified
until actual receipts are available. The unit remains Draft; no merge is done.

B executed [static-checks.json](static-checks.json): two individual pinned
formatter commands, five Node syntax checks, five read-only freshness checks
and whitespace, all exit zero (13 commands). These do not execute the tests.
The Node dependency symlink is read-only borrowed from the protected B
`actql-frontend-qualify-group-aggregate-slots/node_modules` target; its exact
path is recorded in [borrowed-dependency.json](borrowed-dependency.json).

## Normal grouped ROWS main integration

This branch normally merges published main
`d80a30d47ab0d673a0005aa95147bb625e35cb17` after #1471. The submitted
#1471/#1474 heads were not changed. Only packed registration, the inventory
pin and its assertions conflicted; both fixture cohorts were preserved. The
exit-1 merge and original conflicting bytes with SHA-256 remain in
[main-merge-conflicts.json](main-merge-conflicts.json). Upstream grammar,
generated identities, zero-ROWS correction and old preimages remain intact.

The merged registration now has 3,971 declarations (2,495 normal,
50 execution-failure, 1,426 refusal), digest
`9a14391bd66d87985db90c7c0a77ce8088dd93acc4c445768c91d9ead08e1006`.
The earlier 3,957 inventory is retained as pre-integration registration
evidence. [integrated-static-checks.json](integrated-static-checks.json)
records three syntax checks, five read-only freshness checks and whitespace,
all exit zero. Neither this integration nor those checks execute the prepared
regressions or public API. The five normal/five refusal independent oracles
are unchanged. Runtime/public completion remains open.
