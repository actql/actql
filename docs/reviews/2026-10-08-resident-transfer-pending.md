# Resident retained Transfer interruption before commit

The two-task Source acceptance previously interrupted holders only after the
receiver commit or consumer borrow. Neither case proves reconstruction while
the original Transfer still has unwritten chunks.

The Native acceptance checkpoint `retained-transfer-pending` now runs after
the existing retained Transfer Owner confirms one durable chunk and before it
commits the receiver. The existing holder kill/pause options select it. A
holder reconstructed from the original completed producer disables the
historical interruption, as for the two existing handoff checkpoints.
No new execution, holding, Transfer, reservation or cleanup Owner is added.
Default operation, public APIs, wire, identities and limits are unchanged.

## Executed boundary

The existing real-process acceptance selects the new case with
`ACTQL_TEST_RESIDENT_RETAINED_CONSUMER_ONLY=1` and
`ACTQL_TEST_RESIDENT_RETAINED_HANDOFF_INTERRUPTION=transfer-pending`.
It prepares the resident Native executable and matching runtime packages from
one checkout. Selected Node execution is bounded at 60 seconds and uses the
existing nonzero-test guard. Scratch is preserved for the original receipt,
SQLite journals and interruption snapshot.

The read-only interruption snapshot establishes a sealed chunk allocation,
an original Transfer that the common Owner projects as copying, unwritten
manifest chunks, no commit receipt and no borrower. After physical holder
exit, the original producer is reconstructed without acquiring Source again.
The already-sealed allocation retains its exact key, revision and physical
generation. Only the remaining original manifest chunks are added. The
original Transfer becomes committed with one receipt; no new Transfer identity
or consumer start is inferred from holder reconstruction.

The same two-task Run then produces independent expected rows `[{"id":3}]`
and the existing expected schema. The original Source/producer/consumer enter
once each. The acceptance confirms the typed Output ACK, both formal task
releases, zero temporary capacity and pending intents, original receiver
reclamation, bundle hold release and Result reread.

## Initial observation failure

The first attempt (`transfer-pending-native-acceptance-lBrzud`) interrupted and
restored the original holder, but its observer incorrectly required the whole
allocation list to stay unchanged. Completing previously unwritten chunks
legitimately adds allocations. The assertion was split: every original sealed
allocation must be unchanged, and the completed allocation count must match
the original Owner-admitted manifest. No product state transition, independent
Result expectation, timeout or capacity limit was relaxed.

The corrected preliminary attempt (`transfer-pending-native-acceptance-AS5BJZ`)
passed 1/1 in 17.3 seconds on main
`aeaf13f15addf1687c1cd87b12b4657a8c984e9a` plus this uncommitted patch.
Both receipts are retained separately; the submitted clean-SHA result is
reported in the PR after publication.

## Remaining scope

This is real Native plus the existing HTTPS Coordinator fixture, not public
Cloud or Preview acceptance. It does not prove Site generation migration,
Coordinator reconstruction, every cancellation boundary, or historical Run
recovery. Cloud remains on its current formally adopted merged source. Formal
adoption of this checkpoint and public Cloud fault acceptance follow OSS main
integration; no package alias or alternate binary replaces that step.

The public two-task completion unit remains separate from Effect/INFER.
Historical Cloud #88 responsibilities remain open regardless of this new Run.
