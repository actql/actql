# Managed input measurement reuse

This increment connects managed receiving views to a one-use input/output
measurement ledger. It is a common-library component, not yet backend dispatch
or a new-profile end-to-end performance result.

## Evidence and accounting

Initial managed value admission still validates every admitted cell and measures
each top-level canonical value. During that existing pass, it now records exact
bytes/nodes subtotals and maximum value bytes per logical schema column. Storage
is proportional to schema width, not rows. No extra value traversal, row-array
JSON tree, or content hash is used to produce this metadata. Evidence is issued
only after successful complete admission, not from partial/failed input.

`prepare_reused_managed_producer_measurement` accepts the complete, exact checked
managed receiving-port set. It uses the previously admitted logical column
correspondence for projection, rename, reordering and exact copies. A duplicated
column contributes twice to the consumer's bytes/nodes and work. Each consumer
has its own ledger; sharing a material does not share a budget allowance.

Work is the same row-plus-column count as the existing value measurement path.
Canonical value bytes are neither row-record bytes nor physical file bytes.
The exact maximum can discharge a tighter value-size ceiling than the one used
by the producer, including a projected numeric column when an omitted text
column has larger values. Depth compatibility is currently conservative: a
tighter depth than the original successful measuring budget requests a scan.

The remaining ledger transfers once into managed output admission. Output
cannot obtain a fresh full allowance. A sealed receipt carries the exact
session identity and total input-plus-output quantities. It retains neither
upstream material nor liveness closures. The installed verifier can match that
receipt to the session and exact managed input bindings, while live input checks
still apply before completion. This is measurement evidence, not execution,
authorization, physical capacity settlement, or required identity evidence.

## Fallback and limitations

An insufficient subtotal budget, value-size summary, or depth summary returns
`InputRepresentationRequired(index)`. That requests ordinary ordered measurement;
it does not invent the first violation's location. Reuse-search metadata work is
separately bounded and exhaustion likewise requests fallback. No partial ledger
escapes a failed preparation. The Host must account for actual preparation work
and use its remaining overall resources for fallback, not reset its Run budget.

An actual unavailable/foreign input, invalid limits, or known input-row guard
violation is not treated as missing optimization evidence. Consumer expression
evaluation, root-size guards, join demands, authorization and pins remain outside
this API and are not waived. Ordinary managed fallback dispatch is still to be
connected; callers may not turn `InputRepresentationRequired` into success.

These summaries describe all rows of the exact admitted view. They do not yet
derive selected-row subtotals for filter/take/sort or unchanged-column evidence
through derive, and they do not authorize arbitrary caller-supplied row mappings.
Those agreed rules remain required work, along with live Local/DuckDB dispatch.

## Verification cases

- Two rows containing exact integers, accented text and a supplementary Unicode
  scalar; independent expected column byte/node/work totals.
- Projection, rename, duplicate columns and reversed source-column mapping.
- Two consumers each paying the full required logical quantity.
- Tighter value-size acceptance using exact maxima rather than producer limits.
- A 14-byte input/output allowance succeeds; 13 bytes preserves the output's
  row-1/column-0 measurement failure rather than resetting the budget.
- Foreign use-site identity, revoked input, one-use transfer and cancellation.
- Summary/budget shortages request ordered measurement, while exact row guard
  failure remains a failure.

No speed ratio or completion of the registered 1 GiB / 27-case gates is claimed.

Verification passed: `execution_relation` 426 tests on each of JS, Wasm and
native; adapter 22 tests on each target; real Node/DuckDB physical-manifest
integration 4 tests; cross-target public API, full documentation/contracts,
formatting and whitespace checks. The integration rechecks the existing physical
content/retention path; it does not yet dispatch consumers through this new
measurement session.
