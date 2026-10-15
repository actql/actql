# Private continuation retention 0.1

The bounded original-Model Evidence path reads the private
`actql-local-continuation-retention/0.1` record through the existing Source
preserving JSON parser and closed retention projection before native Node
materialization. Duplicate decoded object keys are `InvalidContinuationLedger`,
including identical repeated values and escaped spellings of the same key.
This explicitly tightens the previous private `JSON.parse` last-wins behavior.
Public JSON and Program acceptance are unchanged. Normal owner-produced writer
bytes, references and CIDs are unchanged; no canonicalization or rewrite occurs.

The physical reader snapshots the existing finite safe-integer bounds before
I/O. After the same FD enforces that wire ceiling, the Core ABI receives the
actual byte length and `min(maxLedgerEntries, actual byte length)`. An entry
cannot outnumber its input bytes. Thus large safe-integer Host ceilings remain
valid for small records without wrapping at the Core Int ABI; actual records
of at least 2147483647 bytes refuse before Core parsing.
Missing matching installed Core parsing is unavailable, never a native JSON
fallback. Source parsing admits at most
`min(actual byte length, 14 + 7 * min(maxLedgerEntries, actual byte length))`
value nodes, container depth three,
and bounded UTF-8 input. Seven nodes cover the full root; seven cover each full
entry. One extra entry permits a distinct entries-limit diagnosis. Larger
invalid trees may refuse as `InvalidContinuationLedger` before counting entries.
Decode admission uses the same nodes/depth and wire-bounded string limits.
The closed root and entry schemas still distinguish absent optional fields from
NULL. Data strings, including decomposed Unicode and CR/LF, are preserved.

These are acquisition/shape limits, not heap coefficients or grants. Entry 40
alone is not a parsed-tree or heap bound. The original READ reservation must
cover all simultaneously owned input/probe bytes, decoded input, Source nodes,
fields/keys/backing, parser frames/key-admission/error/number scratch, decode
tree/object maps/cursors, and the subsequent fixed-shape Node object graph.
Their unreachable or rejected intermediates are not credited as physical GC
acknowledgements. Overlap with a retained old ledger, a reread ledger, Store
objects, Promise/FD cleanup and caller-held views remains in the same original
Owner's inventory. Existing unpriced components remain unavailable: these
limits alone do not complete the normal numeric READ profile.

Malformed metadata never proves a fresh, unsent, confirmed or reclaimed
operation. It cannot authorize retry, repair, retirement, resource restoration
or Model send. Original Scope/current selection, Store custody and cleanup
obligations remain separate. Failed FD close preserves the same cleanup carrier
and close-only retry; no replacement pathname read discharges that duty.
