# Managed completion to checked downstream read

The real native completion fixture now proceeds to two checked downstream input
bindings. `ManagedProducerRead` validates the exact receiving use-site against
the completed producer invocation. Its material-match accessor binds installed
representation lookup to that same opaque material, not the integer payload,
path, schema, or digest. A separately prepared but equal producer is rejected.

The installed local Store registry records the material, its Core readable
predicate, exact Store-owned body and adopted codec identity. Before read it
requires current use authorization separately from availability. The Store's
existing generation-bound read grant acquires the pin before exposing a path;
physical integrity and the exact read report are checked before returning.
Authorization and binding are checked again after awaited use. Read failure does
not pretend the source was released or undo a previous independent completion.
Detected physical corruption revokes the affected body.

The helper is for awaited local/native readers. Its callback must settle all
accesses, including on failure, before returning. It must not acknowledge an
unconfirmed remote worker stop. Accepted process delegation still needs its
separate session/stop acknowledgement integration; this local helper does not
narrow the agreed managed-Run contract to one process.

## Evidence and accounting

Each downstream consumer independently invokes the common reusable measurement
rule. It reads column subtotals and maxima from the admitted receipt rather than
decoding or revalidating values. For the three-row Unicode/NULL result, each
consumer independently records six logical work units, 26 value bytes and three
value nodes; the empty result records zeros. The fixture uses literal expected
values and quantities. The physical verification read is charged separately via
the Store callback and still occurs on each file borrow.

The native fixture confirms real Store pins during reads and their release after
success or denied publication. Wrong codec, absent input and initial denied
authorization never invoke the reader. Revocation during an awaited read denies
its result, releases its pin and leaves the previous completed result intact.
Neither the registry nor the measurement accessor issues execution completion or
authorizes an arbitrary logical view.

## Remaining scope

This increment established a checked **read consumer**. The subsequent
[managed native query connection](managed-downstream-query.md) also executes a
checked count consumer in DuckDB. Neither establishes a downstream Local kernel
or the full production managed-input dispatch. The physical transport frames
remain a fixture-only codec rather than a registered public representation.
Finite row-transform evidence
transfer, production requirement derivation and registered physical codecs
remain. The full initial-profile conformance paths and performance gates are
not complete. There is no new performance claim in this increment.

Verification passed: 426 common execution tests on each of JS, Wasm and native;
21 actual native/Store shared-read, direct-file and manifest tests; cross-target
interfaces, full documentation/contracts, formatting and whitespace checks.
