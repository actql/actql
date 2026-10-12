# Source Catalog fixture repair

The original G d62f full-Core evidence remains immutable. This unit repairs one
of the 55 assigned Frontend failures: the derived-right single JOIN GROUP case
was using a Connector Source Context with no admitted Source Catalog. The new
WITH static check correctly rejected that metadata omission before the original
predicate, JOIN ceiling and aggregate could be checked.

## Change and independent evidence

The test-only Context retains `crm/main`, resource `records`, no authored view,
input `source`, logical relation `records`, visible `id`, and the capture boundary.
An independently authored Catalog supplies its sole view and numeric non-null
schema. Empty carrier facts grant neither a key nor an order. No Source, checker,
order owner, Program operation, query text or expected assertion is changed.
The original shared-source JOIN control also uses this same admitted Catalog.

`independent-catalog.json` retains complete envelope preimages. Python hashlib
and sorted ASCII JSON determine each contract/view/Catalog/environment CID.
Registry ordering uses the digest of the complete member, distinct from its
self-CID. The original malformed ordering experiment is preserved, not passed.
A negative control still requires `MissingSourceCatalog` with the original
unregistered Context; the positive control checks the original no-view input.

## Executed checks

- Clean fixture source `9f806131a6e36678c9a0738af643af2b9173e9bb`:
  existing prepared-checks wrapper, explicit `registered_source_context_test.mbt`,
  `single_join_group_test.mbt`, and `lower_test.mbt`: JS **12/12**, run-HmoFIf,
  focused-test-5vTQtW. Existing budget **60 seconds / 5 seconds grace, nonHeavy**.
  Complete exit 0, streams complete, guard lock released; actual Owner 69236 absent.
- Pinned formatter on the changed two MoonBit files: run-V3vtVS, exit 0.
- Earlier 98b9 fixture source: JS 12/12, run-ByJVfq, separate from final source.
- Independent five contract + view + Catalog + environment hashes verified;
  `git diff --check` passes. Raw evidence is preserved outside Git with hashes
  in `evidence-hashes.json`.

## Preserved failures and remaining boundary

06253 Catalog read: run-BjdbOl, 0/3; incorrectly sorted independent evidence.
6f505 Catalog admission: run-neU8gt, 2/3; derived JOIN GROUP succeeds, Pipe fails.
The Pipe diagnostic at e08e2c335, run-KajyLh, gives
`SourceProgram(Program(Order(1, PipelineOrder(UnresolvedOrder))))`, cursor
`stages[1].steps[9]`. It is not fixed by supplying Catalog metadata. Its original
positive fixture has been restored unchanged and remains pending, together with
the two CTE capture order cases. The temporary diagnostic is retained in Git
ancestry and raw logs. The optional Cursor assertion compile error at 13659,
run-KLu6y4, has no executed tests and is not counted as a product failure.

This unit brings the bounded repair evidence to **52/55**; it does not close the
remaining three order cases. No public Host/packed Local/HTTPS, Provider, Heavy,
Native/Wasm runtime, full Core or Hosted CI was run. Catalog static admission and
compiler tests are not public acquisition or publication evidence.
