# Computed-column admission and index merge

The managed view builder now separates unchanged/copied columns from newly
computed columns. It copies bounded occurrence metadata for the former and
invokes the checked-value reader only for the latter. Newly computed values
must carry the exact output field contract; their physical admission and
canonical value measurements are performed once and merged into a new,
independent output index. No row-array JSON or logical CID is produced here.

The deterministic four-column, two-row fixture reads two computed cells rather
than eight total cells. Its merged column byte totals are `[10, 2, 2, 10]`.
The normal output issuer still charges all output columns: logical measurement
is `(work: 10, bytes: 24, nodes: 8)`, while actual builder admission usage is
`(work: 10, nodes: 4, text_bytes: 6)`. These are operation counters, not a
wall-clock performance result or a completed large-case acceptance gate.

Computed value admission does not certify the expression's execution, selected
occurrences, ordering, or physical output material. The result must pass the
installed, scoped execution verifier and ordinary retention/completion path.
No provisional or partially populated index is exposed on failure. Missing
rows/cells, foreign checked contracts, cancellation and reentrant finish are
covered by negative tests.

Measurement failures are provisional witnesses, not automatically the final
public diagnostic. `NeedsOrderedMeasurement` requires resolution against the
complete output ledger and applicable failure precedence. Exact copied-cell
sizes participate in canonical column order, but the builder cannot determine
whether another full-ledger limit has earlier precedence. It therefore cannot
publish a receipt or silently turn this witness into a final diagnosis. The
caller must preserve consumed budgets and resolve the outstanding obligation;
this result is not permission to restart execution or ignore a known violation.

This increment is a Core building block. General native/Local derive execution
and the production fallback/diagnostic-resolution connection remain unfinished.
The occurrence index is bounded by cell count and traversal work; physical
metadata memory reservation is still separate outstanding work. The full
usual-operation pipeline and the original 1 GiB, 27-case paired performance
gates remain required. No legacy identity preimage, contract pin, performance
baseline or acceptance threshold is changed.

Verification: execution_relation passed 442 tests on each of JS, Wasm and
Native. The six existing native DuckDB Compute/manifest tests, strict JS check,
three-target interface generation and documentation checks also passed. These
native tests are regressions for existing paths, not native derive coverage.
