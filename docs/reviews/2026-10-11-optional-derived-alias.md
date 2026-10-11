# Optional table-subquery aliases and preserved output scope

## Selected requirement and original counterexample

The [GoogleSQL table-subquery syntax](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#query_expr)
permits an omitted alias. The fixed
[ResolveTableSubquery reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/googlesql/analyzer/resolver_query.cc#L14834)
keeps the inner NameList when alias is absent (ranges/value-table state included)
and wraps it with the explicit alias otherwise. This is the selected profile,
not a complete standard/vendor conformance claim.

At parent #1347, source 87e58c3246be1d175874abd97154a82fc94a3e2f, this is refused
with Syntax("Subquery requires an alias"):

```sql
SELECT id FROM (
  SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64)
  UNION ALL SELECT 2 UNION ALL SELECT 1
)
WHERE id IS NOT NULL
ORDER BY id DESC NULLS FIRST LIMIT 3
```

Independent rows are 2,1,1, nullable number column id. Without the WHERE,
NULL would occupy the first limited row; duplicates/order/limit distinguish
other incorrect lowering. Independently authored JSON Values/filter/sort/take
already checks. Baseline run-2R0B8O is 1/2: Program passes, source parsing fails.
Keep /private/tmp/actql-b-optional-derived-alias-independent-control.json and
/private/tmp/actql-b-optional-derived-alias-87e58c324-baseline.mbt.

## Scope-preserving connection

Do not just remove the alias requirement and project away valid ranges. Use the
existing projected producer for closed SELECT/set outputs and the existing
private continuation scope for an unnamed query retaining ranges/value-table
receivers. Reuse pipe_join_input_alias to determine the surviving scope. The
new query_output_carries_ranges helper closes set ranges. Explicit aliases keep
the existing projected boundary and replace prior ranges.

Transparent query parentheses preserve the same scope. sql_operand identifies
closed set operands separately from a parenthesized continuation, so old ranges
and private value slots are not exported by UNION/BY NAME. No explicit or guessed
producer alias is invented. Existing builder fresh names avoid all authored names.
The usual projection/SET/DROP/name/key/type/NULL and budget owners remain in use;
no CTE/predicate/Effect owner, parser string rewriting or execution engine is added.

Current versus immutable r.x after SET is covered by independent matched JSON
and rows. Existing input ranges disappear after SELECT and an explicit outer
alias; ambiguous names and private-producer guesses are typed refusals. The
value-table receiver case uses existing checked UNNEST, not row sampling.
Inner order/LIMIT remains in its own query. An outer SQL Relation without ORDER
is not promised to inherit that order; fixtures specify their required order.

## Actual local diagnostics and checks

- run-ymZziY: 10/11; run-hwVbzO: 11/12. The four-term SQL control fails the
  tiny local checker budget, not a semantic rejection. It produces 16 stages,
  23 steps, versus the existing fixture's max_steps=20. The named source control
  fails identically (run-rDrEtF, 0/2).
- run-Q5QKCk: 2/2 confirms both as exact CompileLimit. Do not increase local or
  production limits. Preserve full Program at
  /private/tmp/actql-b-optional-derived-alias-four-operands-program.json.
  Keep that complete original source and expected rows in public acceptance,
  whose actual installed limits are checked by the ordinary Host. The local
  positive uses the same four values via existing checked UNNEST within its
  existing budget, not altered rows/order/predicate/limit.
- run-0QIBBc: 4/5 exposes lost r through double query parentheses. Fix the AST
  binding role; run-Hq7OS7 is 25/25 for new and existing nested/BY NAME/JOIN callers.
- run-o2AO49: 13/14 due a new parser assertion treating hoisted right CTEs as
  still inside the right Query. The existing parser hoists them; correct the
  assertion to inspect both actual CTE bindings at the root.
- run-WihB7B: 10/10, independent complete established producer Program,
  current/immutable ranges, value receiver, transparent/closed parentheses,
  explicit alias replacement, lost-name refusals and exact resource refusals.
- run-AdsnjH: selected query_syntax interface compilation and existing normative
  generators. JS/Wasm/native interface compilation, unsupported wasm-gc skipped.
- run-O8YRsl: independent grammar/current/historical Run and public fixture
  controls/registration, 67/67. Accounting is not execution of unrelated cases.

## Normative pins and independent identity

Grammar self CID changes from f2bf87c10285fe83d42ef8f5f8dd4071b1d21269186acf8abfd335572996f413
to baaa80c2d0c6053f42eb44fc476fd99ec29e42fcfd2035233c6f8e2c12dea26b.
Common Values Unit/ResultPlan/Program remain unchanged; grammar-bound
invocation template, executable/compiled Plan and Run change. Freeze the complete
prior closure in scripts/fixtures/pre-optional-derived-alias-values-identities.json.
Old Run 1d4ff0853432dfbd1d1c92db64aa2a064ae8dcd930bd0b915ecc233b01ee57c2
keeps its old grammar. Current expectation b82a41c233577845b9eaf4c491671994c70305a4a7c707f6fc4f3354a2362d8b
is derived with independent complete preimages/sorted-JSON hashing, not product
output. Preserve /private/tmp/actql-b-optional-derived-alias-current-run-preimages.json
and /private/tmp/actql-b-optional-derived-alias-independent-vectors.mjs.

## Remaining gate and dependency

This is a child of unmerged #1347 (audit/frontend-from-pivot), fixed parent
87e58c3246be1d175874abd97154a82fc94a3e2f. Retain that base until parent reaches
main; do not merge into the dependency branch. Parent's input-consumer projection
fix is needed for the new SELECT * case. Final merge target remains main.

Use normal clean-HEAD five-package producer and existing --query-composition-only
Local/HTTPS acceptance. The entire selected cohort is 43 normal/24 refusals,
including 13 new normal/six typed refusal cases. It includes the complete original
four-operand source, independent JSON, NULL/duplicate/limit/order, range snapshots,
value receiver, both JOIN sides, captured source/nulls and Source session counts.
Record exact source/tarballs/terminal receipt/Named Results in the PR. Local
source/checker success is not public execution or CI success.

This unit does not introduce scalar/correlated subqueries, LATERAL, recursive CTEs,
anonymous public column labels or new value-table/Graph algebra. Previously
unsupported common shapes retain separate obligations. The shared input-only
JSON task-emission gap #1350 is not fixed by this parser connection. No full
Core/all-target runtime/proof/performance/all-packed campaign or merge is claimed.

Final preparation run-zWjtIE checks the consuming Values Run identity 2/2 and
read-only compilation manifest, document metadata, spec family, canonical,
Workers and Node freshness. Pre-submission main remains eefdda1a85c4e033d6dcefcc774095949cc97262;
parent #1347 remains open at 87e58c3246be1d175874abd97154a82fc94a3e2f.
