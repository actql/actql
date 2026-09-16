# Managed physical manifest: Store integration

This increment connects the registered physical-manifest contract to the actual
local retained Store. It is **not** complete managed-profile execution, a new
logical identity scheme, or a performance acceptance result.

## Implemented boundary

`adapters/store-local/managed-manifest.mjs` snapshots closed manifest metadata
under explicit chunk-count, metadata-byte and referenced-byte bounds. It checks
safe-integer count sums, hashes canonical metadata in bounded fragments, keeps
duplicate chunk occurrences in order, and detaches mutable caller containers.
Only ASCII constants, canonical CID strings and safe nonnegative integers enter
this specialized canonical emitter; it is not a generic JSON canonicalizer.

Physical consumption binds expected schema/view/codec pins and each occurrence
to a genuine sealed body issued by the exact installed Store. Matching digests
or a copied JavaScript object do not establish that ownership. It acquires all
distinct body borrows before native access, verifies bytes with the existing
delegated-file reader, and requires the installed decoder's actual row count
to match each chunk. The decoder is a trusted implementation, not independently
proved by its reported count. All output remains provisional until completion
of this physical operation; this result is not ActQL completion or use authority.

Cancellation, failed count/budget checks and partial binding failure release
acquired borrows without destroying an otherwise valid source. Detected file
corruption revokes the affected body. Reclamation still waits for confirmed
reader termination, including later chunks pinned before the first decode.

`integrityReadBytes` counts the verifier's byte scans only, not the native
decoder's separate I/O or all physical work. `referencedBytes` includes repeated
occurrences and is not unique storage usage. No logical row encoding is used
to obtain the physical identities.

## Real DuckDB experiment and discovered constraint

The Parquet integration fixture writes native DuckDB output, seals its physical
bytes in the Store, and reads it twice through the new manifest boundary. Fixed
expected rows verify NULL, Unicode text, duplicate occurrences and ordinal order.
The fixture performs one physical copy before sealing; it does not claim direct
zero-copy output or full ActQL semantic admission of Parquet.

Direct `COPY ... TO` into the old delegated writer's preopened destination was
also tried. With the pinned DuckDB `1.5.5-r.4`, COPY replaces the destination
inode. The existing Store correctly rejects its terminal report with
`StoreIdentityMismatch` and refuses to delete the replacement as though it
owned the original inode. A dedicated regression fixture checks this behavior
and explicitly removes only its own observed replacement during cleanup.
Do not weaken that equality check to make direct output pass. A future direct
producer path needs controlled creation/adoption of the new generation, or a
bounded physical-copy path, with its own binding and lifetime guarantees.

## Verification and remaining work

The new Store tests cover canonical metadata and exact byte ceilings, bad
shapes/counts/overflow, detached metadata, ordered duplicate chunks, foreign
Store/body and interpretation rejection, budget/count failure, corruption
before/during native use, cancellation, cleanup races and empty results.
DuckDB tests cover the positive Parquet round trip and the negative COPY-inode
case. These are integration/conformance checks, not throughput measurements.

Validation passed: retained boundary suite (99 tests), the two new real-DuckDB
cases plus the existing standard Host integration (3 tests), and the full
`npm run check:docs` suite. No new-profile end-to-end timing is reported here.

Runtime profile selection, common semantic completion and scoped evidence
issuance, transformations and consumer validation reuse, multi-consumer
lifecycle admission, formal correspondence and the unchanged 27-case acceptance
experiment remain required. The native fixture's codec/view identifiers are
fixture declarations, not a claim of registered production Parquet conformance.
