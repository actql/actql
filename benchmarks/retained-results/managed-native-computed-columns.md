# Native computed-column transport

The DuckDB adapter and Node Host now accept a compact transport containing only
newly computed columns for a prepared managed computed view. Field names and
physical types are checked against those exact output contracts before data
admission, including empty output. Missing, duplicate, inherited or incompatible
fields do not stand in for new columns. Physical field/value diagnostics map
back to full output-schema positions rather than compact transport positions.

The adapter retains one cumulative physical admission budget across chunks.
Malformed transport, invalid values or failed computed admission close the
receiver; no subsequent finish can publish its partial index. Finishing yields
only a provisional selection. The installed execution verifier, exact physical
retention and common completion are still required. The provisional measurement
witness behavior described in `managed-computed-column-transfer.md` is unchanged.

The native fixture starts with the actual managed DuckDB producer containing
`["日本語", null, "日本語"]` (and separately empty input). DuckDB performs a prefix
take of two occurrences, copies `amount`, and computes numeric `marker = 1 + 1`.
The fixed Host verifies selected native rowids, values and order. Only the
marker column crosses the new product value-admission boundary: two physical
cells rather than all six output cells. Independent expectations include:

- Output admission usage: `(work: 16, nodes: 4, text_bytes: 12)`.
- Full shared input/output logical measurement: `(work: 14, bytes: 58, nodes: 9)`.
- Independently owned output occurrence index: six cells, zero for empty input.
- After original material revocation and actual Store cleanup, two new
  consumers obtain the original-column measurements `[2, 15, 2, 11, 1]` from
  the new index and read the independent physical output. Separate consumers
  also obtain newly computed marker measurements `[2, 2, 2, 1, 0]` twice, after
  the original producer material has been reclaimed.

Native negative cases include inherited-field substitution, incompatible type,
invalid double transport, inconsistent row shape and malformed JSON. They
cannot recover a receipt by retrying finish. Existing exact completion,
single-use, cancellation and physical cleanup tests remain in the suite.

This is product transport wiring exercised by a fixed conformance Host, **not**
a general native derive compiler. SQL and its finite execution verifier are
fixture-specific. The fixture still collects native rows in JavaScript and
writes physical frames. It therefore does not establish the no-control-row-copy
or large-case performance gates. General checked-operation lowering, Local
integration, full ordered diagnostic resolution, physical metadata reservation,
delegated worker lifecycle and original paired 1 GiB/27-case measurements remain
required. No old wire, logical preimage, contract pin or acceptance gate changed.

Verification: execution_relation passed 442 tests on each of JS, Wasm and
Native; the DuckDB adapter passed 23 on each target. Native Compute/manifest
tests passed all six cases, including the new multi-chunk computed-column path
and terminal rejection cases. Strict JS checking, three-target interface
generation, documentation checks and formatting checks passed. These counts
describe test coverage, not a throughput or latency improvement measurement.
