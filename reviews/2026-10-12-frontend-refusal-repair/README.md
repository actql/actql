# Frontend Core repair: exact current refusal boundaries

Base main `b0ae22c042efc04f90c7c279e2cc51aadc4651cf` includes #1617.
This fixture-only unit closes six original frontend failures. No product code,
contract, schema, pin, execution owner, Source, row or capacity changes.

## Adopted rules and independent assertions

- An absent admitted Graph is a missing producer, not generic lack of Graph
  support. The installed keyed-MATCH path returns UnknownRelation. Preserve
  that exact cause in query_program and public source_frontend tests. Retired
  LABELS is instead refused at syntax admission with its existing exact message
  and byte 13. No legacy constructor or property-based label adapter is restored.
- Pipe AS replaces preceding ranges, and a Pure WITH body does not export its
  internal range. Missing references in these two existing JOIN counterexamples
  now fail at column resolution with UnknownColumn. DROP/RENAME ambiguous-key
  controls remain AmbiguousColumn. Original source expressions stay unchanged.
- Integer UNPIVOT row labels distinguish two boundaries. The existing exact
  number profile admits 1 and the decimal/hex 2^53-1 boundary, but integer-label
  lowering is still UnsupportedProjection. Unsafe decimal/hex magnitudes are
  refused in syntax with the exact row-alias reason and independently counted
  prefix byte 45, without rounding. String row-label Program/value oracles stay.
- An unused peer CTE is statically checked, then pruned from execution demand.
  The existing parameterized current-range object ORDER must compile. It retains
  the original declarations, demanded id/score projection and unbound required
  parameters; oa/ob/oc/od do not appear in executable parameter expressions.
  The ordinary checker reports NeedsInputs, not an obsolete unused-CTE refusal.

These follow `docs/spec/query-text.md` (Graph pattern source, Pipe range scope,
WITH producer bindings, exact integer literals) and existing independent range,
Graph parser and UNPIVOT controls. Expected rows and independent complete Program
oracles are neither removed nor generated from product output. The obsolete
blanket Graph expectations are replaced by concrete current causes.

## Exact execution and retained failures

- `93805aefba7085af56d37003ba96ced3abd0193e`, run-S7g6XY: JS23/28, five
  original failures reproduced on current main.
- `c34ef6f2d0cbed00af855f5f4fafa6d60d185eda`, run-tfe1rJ: JS45/49. My initial
  expected missing-Graph witness and missing-range classification were wrong,
  and the new integer label prefix was miscounted. These failures are retained.
  Source inspection established the installed UnknownRelation path; the typed
  diagnostic run-HLBZbM on `3a5fce4e96a536f56d84018a9714b4d88d21332c` proved
  UnknownColumn (JS8/9). The authored ASCII prefix independently counts 45 bytes.
- `3308f5329c66653f0174017de38ab807494717ac`, run-elft4P: JS48/49; the second
  stale WITH-internal range also required UnknownColumn. At
  `29e8c19017a8042a375549f75f988a3b969e7a88`, run-uqmzEB: JS5/5 for that file.
- `ab0cd48f6ade550b497f15c90b2f602f4e029981`, run-R3Mrph: JS **49/49**, eight
  explicit changed/control files; run-QWHgIT: the changed compile_test Graph
  case **1/1** using the exact nonzero `--filter`; run-dJDKvk: read-only pinned
  formatting of all six changed MoonBit files. All complete exit 0. Prior
  formatter-write run-LO4Clk remains separate evidence.

Every guard used 60 seconds/grace 5, nonHeavy. Final Owners 87363/87573/88306
were directly observed absent, and all run locks were released. Later evidence
commit SHA is not substituted for the tested source above. No Host/Local/HTTPS,
packed producer, Provider, full Core, Native/Wasm execution, or Hosted CI.

Use the pinned environment and `prepared-checks.mjs` with explicit existing
file paths. For compile_test, use `--case '*query-only context refuses Graph
lowering without a current definition*' src/query_program/compile_test.mbt`.
This executes one case; it does not claim that file's remaining CTE failures pass.
Raw receipts/logs are preserved and verified locally at
`/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`.
Only their hashes are published in `evidence-hashes.json`.

With #1610/#1617/#1623, this brings bounded repair evidence to **26/55** assigned
original failures. **29** remain, including capture/order, Catalog, any-direction
Graph checking and old producer topology/budget fixtures. #1608 remains frozen,
private lag and typed preparation diagnostics remain preserved. No merge or CI
rerun is performed by B.
