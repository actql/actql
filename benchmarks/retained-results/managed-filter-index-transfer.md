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

The actual integration fixture still obtains zero or one filtered row from a
count. The API and Core support longer ordered subsets, but this increment does
not claim a multirow native filter integration test or general filter/take/sort
chain completion. Those paths, physical index reservations and the original
large paired benchmarks remain unfinished. The fixture index cap is an entry
limit, not a physical-byte reservation.

Verification: adapter tests passed 23/23 on JS, Wasm and Native; strict JS and
all six managed DuckDB/manifest Node tests passed. Interface generation and
format/diff, cross-target public API and documentation checks passed. Existing
logical identities and limits are unchanged.
