# Projected retained measurement evidence

Date: 2026-09-16.

The exact-material measurement cache now retains per-column canonical value
byte/node totals. A checked receiving projection may drop, reorder, rename or
copy columns while reusing those totals. Logical work still charges one unit per
row and one per selected value occurrence; copying a column twice charges twice.
This is not record-byte measurement, and no row-array or Result CID is projected.

The original material/generation, complete row scope, successful value ceiling
and depth remain required. Metadata matching is bounded by `max_order_work`;
exhaustion or missing columns leaves ordinary validation available. Additions
are checked against the remaining consumer budgets before committing any reuse.
An insufficient bound never establishes a violation or diagnostic position.

State is bounded by the checked column count, not row count: one subtotal pair
per measured column. No rows are retained. Successful subtotal ownership moves
from the scan to the single material cache; failed/partial scans do not publish
it. Reuse does not replace the wider cached evidence with a narrower view.

## Verification cases

The common test uses actual checked producer projections over two rows:
`{"n":1,"s":"é"}` and `{"n":2,"s":"😀"}`.

| Receiving view | Work | Value bytes | Nodes |
| --- | ---: | ---: | ---: |
| n | 4 | 2 | 2 |
| s renamed | 4 | 10 | 2 |
| n copied to two columns | 6 | 4 | 4 |
| s, n | 6 | 12 | 4 |

Ordinary scans and whole-value reuse agree with these independent literal
expectations. Tighter work, bytes, nodes and per-value limits compare the first
diagnostic location and partially consumed budget with ordinary validation.
Evidence covering only n cannot discharge a later n/s measurement.

The real DuckDB standard-Host fixture additionally publishes both a wide
id/amount Result view and a narrow id Result view from the same acquisition.
The first count reads the wide view; the second count reads the narrow view.
The second input uses established evidence without a validation SELECT. The
following filter still performs its demand scan. Expected diagnostic counters
are `reusedInputValues=[0,1,0]` and `directInputScans=[1,0,1]`; all three result
CIDs match the independent `[{"id":3}]` expectation, with cleanup confirmed.

Verification passed: `execution_relation` 408 tests on each of JS, Wasm and
native; real DuckDB standard-Host integration; documentation/contracts, public
API consistency, formatting and local links.

This is an existing-contract improvement. It does not establish new-profile
CID-optional completion, cross-material filter/sort/derive evidence propagation,
or the formal 1 GiB / 27-case performance gate. No wall-time speed ratio is
claimed for this increment; the measured runtime change is one fewer validation
scan for the checked projected consumer.
