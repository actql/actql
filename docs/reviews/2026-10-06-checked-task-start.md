# Checked remote task start eligibility

A Run-wide `physicalStartClaimed` boolean cannot describe independent producer
and consumer claims. The Cloud caller needs a task-bound decision before its
existing Run CAS stores that task's exclusive claim.

`prepareTaskPhysicalStart` takes original prepared/compiled/admitted Run handles,
current admitted Coordinator records, the original requested/retained root
identity and a trusted Host claim snapshot. The common Owner checks:

- The retained root identity belongs to the original prepared Program and
  authority, including parameters and input intent; two matching foreign
  requests are not accepted.
- The task and dispatch are the exact saved checked occurrence. Missing intent
  cannot authorize a start and a different dispatch cannot use that claim.
- Dependency readiness comes from the checked graph and complete producer
  evidence. Physical settlement without admitted output proof is insufficient.
- The existing Run physical-start Owner checks current authorization, original
  definition identity, durable reservation, unstarted proof, cancellation and
  pre-start failure. Historical Accepted/running/unknown observations remain
  reconciliation responsibilities even if the Host supplies `unstarted`.

A positive decision is eligibility, not a mutation or execution permit. The
Cloud Host must store the task claim in the existing Run/cancellation CAS domain,
retain the exact Coordinator intent, and recheck current authority at physical
send. An uncertain claim reply sends nothing and reconciles the same attempt.
No scheduler, ledger, reservation, borrow or cleanup state is added here. Input
custody and binding admission remain with the retained-input/Transfer/Site Owners.

The real Native fixture now calls this Owner before producer and consumer
handout. Its existing Site journal provides the exclusive physical start claim;
it does not provide Cloud's Run CAS. Evidence labels `cloudRunStartCas: false`
and `publicCloudAcceptance: false`, so it is not completed public Cloud acceptance.

This depends on #554 and its retained-input parent chain. Formal Cloud adoption
must wait for reviewed main integration and regenerate all five packages and
matching Native binary from that one source. Cloud #138 still needs per-task Run
CAS integration, retained consumer handoff, aggregate publication, both-task
release and actual holder reconstruction. #88 old Run recovery stays separate.

## Executed evidence

- Ten selected Node cases passed through the built shared ABI: four new start
  boundaries, two progress cases and four aggregate Run projection cases.
- Host interfaces compiled on JS, Wasm and Native, plus the JS ABI interface.
- Real Native Coordinator reconstruction passed: Source/producer/consumer
  counts 1/1/1, independent rows `[{id:3}]`, typed Output ACK, both task owners
  formally Released, temporary capacity/payload/intents zero and Result reread.
- Real Native cancellation before consumer passed: counts 1/1/0, exact late
  dispatch/repeated Cancel started no consumer and both task owners released
  with zero temporary capacity/payload/intents.
- Both Native selections used `--strip` and a 180000 ms outer budget. The normal
  reconstruction took approximately 64 seconds; cancellation took 17 seconds.
  Scratch, original journals and evidence logs were preserved.

These checks ran before commit on the modified parent tree. No clean-HEAD
verification, pristine five-package campaign, whole Core/packed suite or Preview
deployment is claimed. The actual producer holder stayed live during Coordinator
reconstruction; holder recreation and production Cloud Run CAS remain unverified.
