# Explicit Graph expectation: F01 closure

This unit fixes the adopted `FROM GRAPH` type expectation. F02/F03 and the remaining carrier surfaces are separate implementation units, not added gates for this change.

## Independent failure and correction

The demanded and unused Events examples in `explicit_graph_expectation_test.mbt` previously both produced an accepted Program (`run-NkwFhi`, counterexample commit `dacbc2a2f58e7f2f07443f10483a5b4928aef652`). The required outcome was authored semantic refusal. The unused case even pruned the invalid declaration from execution. Those observations are retained as failures; they are not expected Program fixtures.

The existing scope resolver now selects the nearest producer independently of requested type. Its actual Carrier comes from the existing checked prefix and is checked before dispatch or alias-only return. An inner Events binding cannot select a same-named outer Graph. The ordinary shared prefix owner still checks unused declarations, Catalog ownership, expression typing, and unresolved obligations. No fake Result, alternate evaluator, Source acquisition, or catch-and-ignore fallback is introduced.

The parser retains the original explicit operand origin before resolving a WITH name. `GraphExpected(Origin?)` carries that fact through SQL and AQL-text to the existing query-invalid diagnostic. It does not disclose a protected Source's existence or infer its type before common admission. The public reason vocabulary and revision stay unchanged.

Tests distinguish marked Relation/Vectors/Events, demanded/unused/root/nested bindings, inner shadowing, and real Graph marker equivalence. Original UTF-8 byte positions are independently fixed for ordinary and Unicode/CRLF source. Missing Catalog still fails through the original binding-preparation owner before a Carrier is established.

## Limited verification

The original dirty-source JS runs `run-Tvg4bI` (7/7), `run-uMRziP` (15/15), and `run-sKZUPS` (16/16, including source origins) are local evidence for those exact working sources, not clean submitted-HEAD or installed-product evidence. `run-LrSEZc` failed before execution due to a test helper typo. `run-UyNy9C` failed its new origin test because the test context referenced a captured Catalog input without Catalog evidence; the final origin case uses source-free VALUES, keeping that protected boundary intact. Both failures remain retained.

Changed-file formatting completed in `run-5fgpDh`, whose following connector generator failed due to missing esbuild. `run-3xiipT` restored the unchanged locked dependencies offline, then completed the existing connector mirror generator and JS interface generation. The package lock and runtime source were not changed by installation. No producer, public packed cohort, Hosted CI, paid Provider, Native/Wasm execution, or full Core was run here.

Run the submitted narrow checks with the pinned toolchain:

```sh
node reviews/2026-10-12-frontend-carrier-continuation/prepared-checks.mjs
node reviews/2026-10-12-frontend-carrier-continuation/prepared-checks.mjs --diagnostics
```

Both use the existing 60-second, 5-second grace, non-Heavy guard and nonzero discovery wrapper. The diagnostics check exercises the real public check function, not Run admission or an installed Local/HTTPS campaign. Those installed scenarios remain pending under F07.
