# Contiguous occurrence metadata

Checked managed take/projection chains already produce one exact source interval.
The adapter previously expanded it into an array of row numbers and Core copied
that array defensively before preparing independent output measurements. Both
arrays grew with the selected row count, despite the interval already being
known.

`prepare_managed_view_slice` now accepts the exact start/count interval and
retains that pair instead. The existing arbitrary-index API keeps its defensive
copy. The managed take compiler uses the interval path after its existing
checked count/offset composition and source-row clamping. SQL, selected values,
order and completion obligations are unchanged.

The new entry rejects invalid/overflowing intervals rather than clamping them.
It still verifies input availability, the checked plan's row-preservation scope,
cell/work limits and required source index. A slice cannot turn an all-rows
projection into a take. The installed executor must still prove the actual
native row correspondence, and common holding/completion remains mandatory.

Measurement and independent cell-index copying still cost proportional to the
selected cells. This change removes the two row-number arrays and their creation
work in the compiled take path; it does not remove the retained measurement
index or finish physical byte reservation. Metadata work charges drop only for
the operations no longer performed; consumer logical ledgers are unchanged.

Fixed tests compare all valid intervals of the two-row nonuniform fixture with
explicit row selections, including empty intervals and end positions. They
check output receipt issuance, identical index cells and summaries, out-of-range
lookups, exact work/cell limits, overflow rejection and revoked inputs. The
real DuckDB take/projection chain tests use the new adapter path, including
offsets, empty results and safe-integer count boundaries.

This is a structural allocation reduction, not a claimed large-case speedup.
The original 27-case, 1 GiB and paired performance acceptance requirements are
unchanged and remain to be demonstrated for the completed implementation.

Verification: execution-relation tests passed 452/452 and DuckDB adapter tests
23/23 on each of JS, Wasm and Native. The six managed DuckDB/manifest Node tests,
strict JS checking, documentation checks and formatting/diff checks passed.
The sole public addition is `prepare_managed_view_slice`; cross-target interface
verification includes this new entry.
