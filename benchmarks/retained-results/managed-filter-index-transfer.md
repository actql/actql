# Filter output index transfer

`prepare_managed_filter_selection` binds observed source occurrences to the
checked managed filter/select plan. It enforces strictly increasing, in-range
indices and bounded metadata preparation, then uses Core's independent copied
measurement-index path. It rejects arbitrary permutations and duplicate source
occurrences: this compiler preserves input order, it does not implement sort.
The installed verifier remains responsible for predicate truth/completeness,
the exact attempt, native output and holding. The index alone proves none of
these execution claims.

The Node conformance path now enables an index while initially validating the
count result, executes occurrence-bearing filter SQL, and passes those exact
returned indices to the selected-output issuer. It no longer uses the special
zero/one-row aggregate-facts callback for the preserved filter. After common
completion, two independently bound downstream consumers can prepare selections
from the filtered output's own index. There is no new value-admission pass on
the preserved path. The ordinary-admission leg remains as a control.

Demand accounting still runs: a false comparison needs five logical bytes,
and an empty output does not make it pass a four-byte ceiling. Negative and
out-of-range indices and duplicate occurrences are rejected before issuance.
Late material cancellation, authorization and execution verification retain
their existing checks.

The actual integration fixture now also consumes the independently retained
computed derive output after its original ancestor has been reclaimed. DuckDB
produces two rows with the same numeric `marker = 2`, alongside copied text
columns. A subsequent native `marker > 1` filter and `marker`-to-`n` projection
return source occurrences `[0, 1]`: equal content does not collapse distinct
row occurrences. An empty-input control returns no occurrences. Both ordinary
value admission and preserved-index issuance pass through physical holding and
the same managed query completion. The preserved leg admits zero new values,
retains two measurement-index cells, and supports two independently bound next
consumers without readmitting those values. Reversed, duplicated, negative and
out-of-range occurrences are rejected.

The two true comparisons still charge eight logical predicate bytes. A
four-byte input ceiling rejects the nonempty derive input because its unchanged
text columns exceed that ceiling, even though the filter and projection only
use the numeric column. This is distinct from the count fixture's false-result
predicate ceiling check. The fixture writes a numeric file view of the actual
native result for direct DuckDB import; it is not a new production codec.

This remains a small conformance fixture, not a throughput measurement. Its
multirow predicate retains both rows; arbitrary larger partial subsets, general
filter/take/sort chain completion, physical index reservations and the original
large paired benchmarks remain unfinished. The fixture index cap is an entry
limit, not a physical-byte reservation.

Verification: adapter tests passed 23/23 on JS, Wasm and Native; strict JS and
all six managed DuckDB/manifest Node tests passed. Interface generation and
format/diff, cross-target public API and documentation checks passed. Existing
logical identities and limits are unchanged.
