# Bounded per-occurrence measurement metadata

Original managed output measurement can optionally record each cell's canonical
value byte count, node count and NULL flag. The measuring loop captures these
facts when it already has the cell and encoder measurement; it does not decode,
admit or encode the value a second time. No values or canonical strings are
stored in the index. Ordinary outputs do not enable it automatically.

The index has an explicit maximum cell count, checked before receiving another
row. Exceeding it closes admission and clears provisional metadata before the
next row reader is called. Only fully admitted and measured output seals an
index into its receipt. The opaque index cannot be mutated through public APIs.
The cap is a metadata entry bound, not a claim about allocator bytes: production
Host resource reservation and measured metadata memory still need integration.

Given a checked view plan and exact input row occurrences, the bounded metadata
reader returns exact selected bytes/nodes/maxima/NULL counts for unchanged and
copied columns. Computed columns remain unknown. It rejects duplicate or
out-of-range occurrences, invalid all-row/permutation shapes, missing indexes,
expired inputs and insufficient metadata work. Facts remain conditional on the
adopted executor proving that these are its actual selected rows; an arbitrary
index array is not an execution proof or an output receipt.

Tests use nonuniform UTF-8 values with four- and six-byte canonical encodings,
partial/reversed/empty selections, copied columns and unknown new columns.
The native fixture additionally captures the index on real DuckDB output:
`["日本語", null, "日本語"]` has three indexed cells, and occurrences `[0,1]`
produce `(rows=2, bytes=15, nodes=2, maximum=11, nulls=1)` without reading values.
The empty native output seals a zero-cell index. This fixture tests the metadata
reader, not execution of a new native take operation.

The aggregate-only view issuer explicitly rejects a requested per-row output
index which it cannot populate. Future propagation must bind a newly populated
index to actual output occurrences, not claim index availability merely because
the source has one. General producer/consumer integration, memory accounting,
and the registered large-case performance gates remain unfinished.

No normative identity, old contract, pin, baseline or performance threshold
changes in this increment.

Verification: execution_relation passed 435 tests and query_integration passed
275 tests on each of JS, Wasm and Native. Native Compute/manifest tests passed
all six cases; documentation and formatting checks passed. No large-case
throughput or memory improvement is claimed from these small fixtures.
