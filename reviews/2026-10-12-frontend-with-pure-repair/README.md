# Frontend Core repair: Pure WITH placement and unused binding demand

Base main: `08c8e0789379dea824ad441ec816fcef39e2efef`. This fixture-only
unit closes five of G's original 55 assigned frontend failures. It changes no
parser, lowerer, checker, execution owner, contract, pin, or source acquisition.

## Independent adopted meaning

`docs/spec/query-text.md`, “WITH producer bindings”, requires every authored
binding to receive static checking, even when unused. A valid unused binding is
not an execution root. Pure WITH and derived bodies exclude RESULT. This is an
adopted cutover rule, not a new restriction invented for these tests.

- Move Pure RESULT refusal assertions to syntax admission and require the exact
  existing message and authored token offset/source path. Terminal RESULT's
  independently authored complete Program comparisons remain unchanged.
- Keep grouped-star InvalidQuery and theta-JOIN UnsupportedJoin checks.
- Replace unconditional unused-WITH UnsupportedCte with common-checked demand
  pruning: demanded `x > 0` survives, unused `y = 20` does not affect the Values
  input. The declared rows imply independent output values [1, 2]. No runtime
  or Host I/O claim is made from this structural/checker test.
- Preserve the exact missing outer relation witness after a valid unused body.
- Admit a Pure derived Graph-to-Relation body at the parser and retain its graph
  source and range alias. Semicolon, unclosed-body and nested-INFER refusals stay.

Existing static type/missing-Catalog, demand-pruning, placement, demanded capture
order and unused-LIMIT order regressions run as controls. No input order or
Catalog evidence is fabricated. No assertion or independent JSON oracle is
removed or generated from product output.

## Exact executed evidence

- `fa65f7a262e9f888f08e1f84d164f0b5f7ff2aa3`: run-MyisBW JS 15/24; the
  original nine failures in seven selected files are retained.
- `20c581bb0f7e3a27f6d01bc7fd102b1406a9ac57`: run-RZtAMa JS 32/34. Two new offset expectations were wrong by
  one byte. Their correction counts UTF-8 bytes in the authored ASCII prefixes
  independently; it does not use returned spans as an oracle.
- `a839beb60f1cca693ca70f0d3ecb90d13d11fa0e`: run-VV3xdR JS **37/37**, eight
  explicit fixture/control files, complete exit 0. run-RQExHB read-only pinned
  formatting on the four changed MoonBit files passed on the same source.
- Prior formatter-write receipt run-lqkzq1 is retained separately.

Separate diagnostic-only branch `repair/with-preparation-diagnostics-20261012`
retains typed causes for four other original failures. At `7732f9901e7665aaf797a96609d8f51a5477dfdc`,
run-4nGwGA JS 1/5: capture CTEs fail with LocalProgram.Order(stage 1,
PipelineOrder.UnresolvedOrder); derived JOIN source_frontend callers fail with
MissingSourceCatalog because their test context has no actual catalog. These
four are **not repaired by this PR**. run-Q0zcMX failed before any tests because
my diagnostic helper omitted its error effect; that failure is retained too.

All guards used 60 seconds / grace 5 seconds, nonHeavy. Final run Owners 76860
and 77323 were observed absent; receipts record terminal completion and released
locks. No Local/HTTPS, packed producer, Provider, Native/Wasm execution, full-Core
or Hosted CI was run. The later documentation HEAD is not substituted for the
exact tested SHA.

Raw command/receipt/log bytes are verified local copies at
`/Users/t14i/workspace/20260822/reviews/2026-10-12-b-frontend-core-repair-evidence`.
Only verified hashes appear in `evidence-hashes.json`; no raw logs are published.
The exact bounded command is `prepared-checks.mjs` with the eight files named in
the test source list below, under the checked-in MoonBit and pinned Node paths.

```sh
node reviews/2026-10-12-frontend-with-pure-repair/prepared-checks.mjs \
  src/query_program/semantic_query_refusal_test.mbt \
  src/query_program/unresolved_relation_test.mbt \
  src/query_program/pipe_result_test.mbt \
  src/query_syntax/nested_query_test.mbt \
  src/query_program/with_binding_preparation_test.mbt \
  src/query_program/with_binding_demand_test.mbt \
  src/query_syntax/query_context_test.mbt \
  src/query_program/with_binding_static_order_gap_test.mbt
```

#1610 repaired five Graph-role fixtures and #1617 repaired ten receiver fixtures.
This independent unit brings bounded repair evidence to **20/55** original
frontend failures. The remaining **35** require separate diagnosis/repair. G's
original full-Core result remains evidence for its original SHA, not this unit.
#1608 remains frozen; private lag and the other diagnostic branch are preserved.
