# Native managed view output connection

The Node Host can now finish a scoped managed view issuer through its existing
retention and managed-input Compute completion APIs. A view receiver cannot
accept physical cell frames. Ordinary validated receivers remain available.

The real DuckDB test executes the compiled `n > 1` filter/select over a retained
count result, with the actual bound parameter and verified direct file import.
It runs both ordinary admission and preservation-based output issuance. Native
rows are checked against independent fixed expectations, physically retained,
and passed through the same common completion and predicate-demand checks.

For the preservation path, no output frame is sent to `managedOutputAccept`.
Core admission work/nodes/text are all zero; the ordinary nonempty control has
positive admission work and nodes. Both paths retain identical logical charges:
input plus output is `(4,2,2)` for the retained row and `(2,1,1)` for no output.
The false predicate still requires five logical bytes: a four-byte ceiling
rejects completion even when no output row remains. That failure is terminal.

## Exact scope of this evidence

The native fixture issuer is restricted to selecting zero or one rows from one
already validated scalar count. It can transfer exact column measurements for
the selected row without scanning; the empty selection has zero measurements.
It does not infer arbitrary-subset totals from a whole-column maximum. The
installed test Host binds actual query settlement, current receiving view and
the sealed output. This remains a trusted implementation boundary, not an
independent proof of DuckDB correctness.

This connects the production Host boundary to real native execution. It does
not yet implement a general production issuer for multirow selection, newly
computed columns or the full projection/filter/derive/sort/take chain. Those
paths must supply their actual scoped measurements and validation evidence;
the required scope has not been reduced to this count/filter example.

This is not direct native output performance evidence: the small fixture still
reads native rows into JS and stores its physical frame encoding. General
direct output, Local integration, managed worker lifecycle integration and the
registered large-case paired measurements remain outstanding. Old preimages,
pins, baseline and acceptance thresholds are unchanged.

Verification: the native Compute/manifest tests passed all six cases;
query_integration passed 275 tests on each of JS, Wasm and Native. These are
correctness/accounting checks, not a throughput or speed-ratio claim.
