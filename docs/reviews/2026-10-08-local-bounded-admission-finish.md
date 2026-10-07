# Bounded managed-admission receipt issuance

## Completion unit

The Local managed finalizer previously walked every reference row, input and
column counter and copied all receipt containers in one finish call. Its outer
driver yielded, but that receipt traversal itself did not.

`advance_managed_output_values_finish` now retains that traversal in the existing
admission owner. Each step visits one reference, container boundary, producer
input or fixed-size column fact. The Local managed finalizer resumes it with the
remaining quantum and charges the existing finalization budget cumulatively.
No new scheduler, retention authority, ledger or wire representation is added.

The successful common issuer transfers the independently built receipt facts
and measurement index exactly once. Late append, reentrant finish and competing
blocking finish are rejected. Reference and producer authority callbacks remain
the existing validators; receipt identity is not execution authorization.

Cancellation immediately revokes admission. Partial receipt copies remain owned
scratch and retire through the existing reclamation cursor. Neither cleanup nor
the release witness can restart Compute or release pending reservation roots.
Successful transferred receipts remain separate from admission scratch.

The existing blocking common API drains this same cursor. It is not a second
receipt implementation, but callers of that API are not thereby interruptible.
The changed Local managed finalizer uses the resumable API. The row-file
materializing finalizer is a distinct current provider, not a compatibility
fallback; its receipt path is outside this completion unit.

## Independent evidence

For 100 two-column scalar rows, receipt traversal takes exactly 607 steps across
quanta 1, 7 and 64: 600 row/column boundaries, three phase transitions, two column
facts, the column-to-issue boundary and issuance. Admission content usage remains
700 work units, 300 nodes and 400 Text bytes. For 80 one-reference rows, 406
steps invoke the existing authority callback exactly 80 times, with at most one
callback per quantum-one poll. These expectations follow authored input and
the stated phase transitions, not successful execution telemetry.

Partial-copy cancellation, resumed reference revocation, callback reentry and
disposal retain the owner until all independently counted roots are retired.
The actual Local driver fixture cancels after 100 admitted rows and eight receipt
steps, before any material exists; completion is refused and capacity stays
charged through cleanup without increasing provider work.

The standard Host regression uses an installed Events-to-Relation Program and
real retained/publication Stores. Its selected filter task has two output rows.
Quantum-one finalization reaches progress four with no retained material: two
row admissions followed by the receipt's first row and column roots. The test
then delivers cancellation through the Host, checks physical stop, no terminal
producer/consumer publication, no committed index, no redispatch and final zero
reservations/holdings. It does not substitute a sleep duration for that boundary.

## Preparation receipts

These executions observe dirty implementation at parent
`1c39293c366e2aac98bfce8aded06cebfb1c5587`; they are not clean submitted-HEAD
or CI evidence. Receipts are retained under `_build/local-checks/attempts` and
`_build/focused-evidence` in the author's worktree.

- Common cursor, existing admission/reclamation, Local finalization and Values
  caller selection: JS 38/38, `run-7qVwBH` / `focused-test-ArrBAR`.
- Cursor, existing view/verified-output and producer callers, Local finalization:
  JS 22/22, `run-fgY1YB` / `focused-test-OMzwR3`. The later defensive private
  blocking-finish guard is not covered by this particular execution.
- Actual managed Host receipt cancellation: Node 1/1, `run-3KEeXB` /
  `focused-test-riuzRm`, consuming the affected source runtime.
- Local Node and DuckDB conformance JS release roots were canonically rebuilt:
  `run-NgnxQq`, 40 tasks. Canonical Node Host and Workers fixture checks passed.
  These are checkout runtime artifacts, not packed packages.

The initial Host cancellation probe incorrectly selected a row-only Store route,
where the changed managed finalizer is not used. It published successfully and
the new assertion failed. Its 8/9 receipt (`run-1irEsh`) is not a product
counterexample or passing acceptance evidence. The corrected regression selects
the actual managed Carrier-to-Relation route. Diagnostic `run-5QIOul` failed
before discovery because MoonBit was absent from that command's PATH; subsequent
commands use the pinned toolchain. Failed attempts remain recorded separately.

## Remaining boundaries

This unit bounds common receipt traversal, not the duration of trusted callbacks,
allocator/collector operations, nested-value admission, other synchronous
availability walks, every Store finalizer or Native physical-byte lifetime.
Wasm/Native execution, pristine packed/HTTPS acceptance, full Core/proofs and
submitted-HEAD CI are unverified. The full retained Local goal remains open.
