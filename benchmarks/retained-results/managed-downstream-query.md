# Checked managed input to native downstream query

`ManagedFixedQuery` binds a single-input native query to the exact
`ManagedProducerRead` use-site. It compiles the receiving owner's existing
FilterSelect/CountGroup realization and typed input table using the existing
compiler; it does not invent a legacy `ProducerRead`, row CID or output CID.
Unsupported native shapes remain adapter limitations, not new language rules.

The handle is preparation, not admission or execution proof. A match requires
the same receiving binding and currently available material. Even a separately
prepared use of the same completed output does not match. SQL remains readable
after revocation, but possession of SQL cannot authorize dispatch. Representation
matching, guards, demand, a Store pin, current use authority and resources remain
the Host's responsibilities. The compiler does not grant them.

## Actual native test

The native managed-completion fixture now creates a checked global count
consumer of its independently retained output. It charges the input using the
common reused measurement rule and executes the compiler's SQL in another
bounded, single-thread DuckDB instance. The Store's awaited native-read boundary
holds the exact body pin during use and rechecks the binding before return.

The fixture's explicit frame decoder uses DuckDB `read_json` and list expansion
to import its one nullable string column. There is no JS cell decode, parameter
INSERT, repeated Core value admission or logical input CID generation on this
leg. The output expectations are literal: Unicode/NULL/duplicate input gives
`n = 3`; empty input gives `n = 0`. The compiler emits an ActQL number (DOUBLE),
not a raw DuckDB BIGINT. A foreign receiving use is rejected, and revoking the
material invalidates the prepared query's binding. Store pins return to zero.

## Limits of this evidence

The physical frame codec is still fixture-only. This test does not register a
general JSON, Parquet or Arrow representation and does not demonstrate arbitrary
view decoding. At this increment the count result was only an independent native
test observation. The subsequent [downstream completion connection](managed-downstream-completion.md)
adds common managed completion and independent holding; production dispatch is
still incomplete, and this is not an ActQL ResultArtifact.
Full filter/derive/sort/take chains, Local execution and
managed process delegation remain required by the original goal.

No performance acceptance is inferred from this small fixture. The registered
27-case/1 GiB paired gates and separate new-profile measurements remain pending.

Verification: actual managed native completion/downstream test passed for empty
and populated inputs; 275 query-integration tests passed on each of JS, Wasm and
native. Cross-target interface generation, documentation/contract checks and
format/whitespace checks passed. The native test also keeps the prior transport
revocation, policy revocation and Store cleanup cases.
