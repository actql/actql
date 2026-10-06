# Graph order scalar emission

Base: union #485, `471267807c53d659279109707359e7806954f5d1`.
The repair is a separate dependent review unit. Its final destination is main
after #485 is adopted; it must not overwrite the Graph owner's branch.
Subtraction #501 inherits the same order owner and must adopt the parent repair.

## Failure and bounded correction

`advance_complete_order(cursor, 1)` previously emitted an entire Text or object
name through synchronous `encode.string_value`. A 4096-character Text wrote
4107 bytes while reporting one emission work unit. The failure was reproduced
against exact source/dependency blobs from #485 and #501, not a copied helper.

Text and object-name emission now retain the existing `StringEmitCursor` as one
private pending order frame. Each physical transition emits at most the common
64 UTF-16 units, completing a crossing surrogate pair together. LIFO scheduling
keeps that emission exclusive until completion; a child or closing bracket
cannot overtake it. Cancellation closes the pending emission and the existing
writer, without reclaiming the borrowed input. Failure also closes the writer
when the failing emission frame has already been popped.

The typed order wire, byte/node/depth ceilings, recheck usage, logical Store
charges, set semantics and existing Session/cleanup owners are unchanged.
`complete_order_key` still drains this same cursor. There is no second encoder,
comparison meaning, scheduler, runtime owner, schema or identity.

This closes scalar **emission**, not every Graph scalar scan. Raw identity/order
string comparisons and the existing synchronous object-name recheck remain
separate work. Final string materialization retains the common writer contract.
No uniform whole-Graph stop-latency or physical heap guarantee is asserted.

## Independent control work

The work-count approach follows the existing #498/#540 distinction: count actual
bounded physical phases once, without adding a charge per resume or changing
logical charges. The same input must retain its total for quanta 1, 7 and 256.
No product ceiling is increased and one-short refusal remains required.

For a Text requiring C fixed scanner chunks:

- Recheck: one value node, C chunks, one terminal = C + 2.
- Typed order: one value/setup frame, C emission chunks, one terminal = C + 2.
- Total = 2C + 4. A 4096-character ASCII Text has C=64, so total work is 132.
- Its logical usage remains one node and 4096 bytes. The canonical order key
  has eleven framing bytes, so output quota 4107 succeeds and 4106 refuses.

Escaped Text uses the same source-unit chunks, not escaped output length.
The independent escape fixture has six chunks and work 16. A fixture beginning
with 63 ASCII units plus a surrogate pair crosses the first boundary together;
its independently enumerated four chunks give work 12. Expected output strings
are authored in the tests, not generated from the product.

For one object field with a 384-unit name and Number value:

- Existing recheck: root, two field visits, Number, terminal = 5.
- Emission: two values, two field visits, entry/aggregate closes, terminal,
  and six name chunks = 13.
- Total = 18. Logical usage remains two nodes and 384 bytes.

For the Graph `set_union` property caller with one 4096-character Text on the
left and an empty right:

- Set setup/read: 2.
- Candidate recheck: 66; typed order: 132.
- Empty-peer comparison/sort: 2; input exhaustion: 2; output transitions: 2.
- Final one-item array recheck: 69.
- Total = 275, independent of quantum, with unchanged result and input values.

The inherited `[null,"a"]` complete-order fixture already failed on unmodified
#485: actual 16, expected 15. Its existing Text recheck requires eight phases,
not seven. Old emission requires eight; the new Text emission adds one bounded
chunk, giving nine. The corrected exact total is independently 8 + 9 = 17.
The failed baseline and the initial incorrect 16 repair expectation are retained
as failed receipts rather than hidden or counted as successful verification.

## Verification

All local execution uses the pinned MoonBit toolchain, bounded/nonzero wrappers
and JS with `--deny-warn`. Working-source receipts before final publication:

- Value admission plus Graph property/fold files: 168/168, `run-HhHp0V`.
- Actual Graph query-integration/custody files: 8/8, `run-xtpMZ1`.
- Restored final code, including mid-string failure and the stronger fixed
  cancellation barrier: combined selected JS 176/176, `run-NhTb34`.
- Selected value-admission/Graph public interfaces agree across JS/Wasm/Native
  with no generated API changes; exact changed-file formatting and whitespace
  pass, `run-WENs1I`. This is interface inspection, not three-target runtime.
- A synchronous-drain substitution in only the new order frame executes both
  named Graph caller regressions and fails 0/2, `run-GotF7N`: it passes the
  fixed in-flight cancellation barrier too early and reports work 212 instead
  of independently derived 275. The implementation was restored afterward.
  Two earlier malformed mutation edits failed compilation and are retained as
  setup failures, not mutation-detection evidence.

The new tests retain original input data, exercise in-flight cancellation and
repeated cleanup, enforce exact/one-short output and control boundaries, and
verify failure inside an unfinished string chunk. No private partial key can
become a complete property. The new cancellation fixture is a real Graph
property-cursor caller; it is not a new public Host or packed cancellation test.
Existing selected Graph integration tests separately cover Session custody.

Final-source rerun, format/API checks and exact publication/CI state are reported
in the PR. Full Core, Wasm/Native runtime, packed Local/HTTPS, Cloud, new Store
failure campaigns, #550 parent observation and whole-Graph resource acceptance
are not established by this bounded repair.
