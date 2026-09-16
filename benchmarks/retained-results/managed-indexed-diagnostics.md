# Ordered rejection from retained measurements

The managed view issuer still uses aggregate column facts for the ordinary
successful path. Holding an occurrence index does not add a row-index scan to
every successful consumer. When aggregate facts instead indicate a measurement
work/bytes/nodes/value-ceiling failure, a sealed exact index can now resolve
the rejection in logical row/column order, without reading or encoding values.

Resolution follows the ordinary `measure_input_values` order: charge a row,
charge a cell, check encoder resource sufficiency, then check the completed
cell's value-byte ceiling. The same typed cause and logical position are
returned. The consumed prefix of the actual shared ledger remains consumed;
the terminal failure cannot be retried with a reset allowance. No receipt is
issued. Execution verification and input liveness still precede resolution.

The index contains exact byte/node totals, not a complete proof of every
possible condition. Existing depth bounds must establish depth admissibility
before this path is used. Missing index, insufficient depth evidence, and
physical admission/row-capacity ambiguity still require the existing additional
validation route. The computed-column builder's provisional failure path is
unchanged; this does not claim its missing ordered-resolution hookup is done.

The differential fixture checks 2,688 combinations of work, byte, node and
per-value limits against ordinary managed value admission/measurement. It
compares success/failure kind, row/column and remaining measurement ledger.
Separate fixed cases establish that the first violating row is returned rather
than the row containing the maximum, insufficient depth evidence is not silently
accepted, and failed execution proof or revoked source cannot produce a value
diagnostic or consume that measurement ledger.
Whitebox corruption injection also checks that an index contradicting the
aggregate failure cannot turn that failure into a successful receipt.

The input values in the differential fixture were already validated and their
index sealed. This is not permission to skip initial admission, demanded
expressions, authorization or physical integrity. Nor does an index become a
free allocation: physical metadata reservation and the full pipeline/large-case
acceptance work remain unfinished. Legacy identities and resource ceilings are
unchanged. These tests measure diagnostic equivalence, not large-case latency.

Verification: `execution_relation` passed 447 tests on each of JS, Wasm and
Native. Strict JS checking, the six managed DuckDB/manifest Node integration
tests, documentation checks, format/diff checks and cross-target public API
checks passed. No public API or identity preimage changed in this increment.
