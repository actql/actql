# Native multirow selection and independent index reuse

The Node Host now exposes the selected-index issuer through the same output
retention handle and common managed completion boundary. Its installed
completion verifier remains responsible for the selected operation's duties;
physical holding alone cannot qualify an output as completed.

The actual DuckDB conformance path imports the managed text/NULL frame file,
selects the first two rows in source-occurrence order, and compares the returned
native occurrences with the prepared checked take/projection map. Native values
are checked against fixed expectations and saved as a separate physical frame.
Both ordinary validation and index-preserving issuance are exercised.

For `["日本語", null, "日本語"]`, both paths charge the input plus output as
`(work=10, value_bytes=41, nodes=5)`. The selected output's exact column facts
are `(rows=2, bytes=15, nodes=2, maximum=11, nulls=1)`. Preserving issuance has
zero Core value-admission work; the ordinary nonempty control has positive work.
The empty case also completes with zero logical measurements and a zero-cell
index on the preservation path.

After the original material is revoked and its file physically reclaimed,
both selected results remain readable. Two new checked consumer uses read the
independent files; the preservation path additionally reads its transferred
measurement index twice. Completion cannot be repeated, and abandoning the
settled native verifier does not undo an independently retained completion.
All holdings are cancelled/closed and resource reclamation checked at test end.

## Limits of this evidence

The take SQL and adopted-verifier setup are fixed conformance Host wiring,
not a general production multi-operation native compiler. They execute real
DuckDB and product output/retention/completion APIs, but do not establish full
projection/filter/derive/sort pipeline deployment. Native output still passes
through JS for fixture storage; direct output and large-case throughput are
not proved by this test. Local integration, newly computed column indexes and
Host metadata-memory reservation remain outstanding.

No old contract, identity preimage, pin, baseline or performance gate changed.

Verification: strict JS checking, all six native Compute/manifest tests,
cross-target interface generation, documentation and formatting checks passed.
This increment changes JS Host/conformance wiring, not common-core algorithms.
