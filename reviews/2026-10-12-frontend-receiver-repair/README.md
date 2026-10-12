# Frontend Core repair: explicit object columns under range shadowing

Base main: `6cc0aebed58e375cf61a17e54c0bd3763ca499f5`. This unit closes
10 of G's original frontend failures in eight fixture files. It does not
assert that the remaining frontend or full-Core failures are repaired.

## Independent adopted meaning

`docs/spec/query-text.md`, “Pipe column and range scope”, defines an ordinary
Relation range as the non-NULL closed row object and says its name shadows a
same-named column. Parentheses do not change resolution. The existing independent
`range_name_precedence_test.mbt` tests the same shadowing, including a parenthesized
receiver. Thus `(payload).score FROM objects AS payload` reads the row's score;
`(payload.payload).score` reads the row's nullable object column and its member.

Eight older fixtures assumed parentheses made the hidden same-named object
column visible. Their explicit object operands are now range-qualified, keeping
the intended contrast with `payload.score` in GROUP/OVER/aggregate reuse and
DISTINCT ordering. The GROUP quoted case keeps a case-varied range identifier;
its object member uses the exact declared `score`. No independently authored
JSON control line, source row, predicate, arithmetic, output column or capacity
changed. The complete GROUP Program comparison remains intact.

A missing lexical receiver still fails with originated UnknownReference.
A known ordinary row's missing member reaches the common checker and is rejected
with the exact existing Operation(Expression(UnknownField("missing"))) cause.
This preserves refusal at the correct owner rather than asserting an obsolete
lexical failure. No product code or common contract changed.

## Exact executed evidence

- `8f68e50bc4768268c55b1ccc36390e10870149d4`: run-BLpomL, JS 11/17 (six failures), original receiver fixtures.
- `373c4a8d62ce3e8ff06d297a008a4ab1af60ee46`: run-6b5tlE, JS 16/17; remaining known-row-member case
  demonstrated ordinary object projection, not a lexical-reference refusal.
- `af37a5deecaf9eaeeafc3c052fe775d2827485fe`: run-0BJbL3, JS 27/27 with common-property and range-shadow
  controls. Same source run-Q1l5Rc independently reproduced four additional
  aggregate/DISTINCT failures, JS 17/21.
- run-QxvFkq used a nonexistent control filename and executed zero tests, exit
  255. It remains a preparation failure; counts are unavailable, never a pass.
- `7583660e18eba756055c1b4f645646be1899d849`: run-5tYCmC, JS 48/48 across the eight changed files and
  existing pipe_range_property/range_name_precedence controls; complete exit 0.
  run-qHS3SA passed read-only pinned formatting on the eight changed files.
  Prior formatter-write receipt run-Vri2OQ is separately preserved.

All guards used timeout 60 seconds / grace 5 seconds, nonHeavy, with lock release.
Use the pinned environment and `prepared-checks.mjs` followed by explicit existing
files. `--format` is read-only; `--format-write` runs the pinned formatter.

Raw receipts/logs remain at
`/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`;
verified copy hashes are in `evidence-hashes.json`. Evidence belongs to its exact
SHA, not the later documentation HEAD. No Local/HTTPS, package producer,
Provider, Native/Wasm execution, full-Core or Hosted CI was run.

#1610 separately addresses five Graph-role fixture failures. With this unit,
15 of the assigned 55 failures have bounded repair evidence; the remaining 40
CTE/topology/scope/refusal cases require independent diagnosis. #1608 remains
frozen and lag remains unpublished. Root's copy_sga_argument fix is not edited.
