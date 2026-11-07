# Completed segment input provenance

- Responsibility: The existing execution completion owner provides a borrowed
  view of an actual completed segment and every external operation input used
  by its provider. The view issues no completion, task success, reservation,
  Source permission or Model grant.
- Inputs and outputs: Construction receives the original CompletedOutput,
  GeneratedSequence, ordered (consumer step, port, ProducerRead) tuples and a
  finite walk limit. A successful view borrows those originals. Reading it
  requires the same sequence and complete ordered tuple inventory.
- Identity: The selected sequence owner and terminal step must match the
  completion. A bounded graph walk verifies every external edge exactly once,
  in step/port order; internal segment edges cannot be supplied as captures.
  Subsequent borrowing requires identical read objects, not merely equal
  bindings, values, schemas or wire identities. Readmitted status and original
  result identity, receiving bindings and representation remain unchanged.
- Ownership: The view retains the original output, sequence and a copied array
  of borrowed immutable tuples. It creates no cleanup owner. Only the trusted
  provider caller may supply the reads that the actual execution consumed.
  The original provider/scope must remain retained until downstream borrowers
  acknowledge retirement. A returned output does not transfer that duty.
- Synchronization: The tuple array is copied before liveness callbacks.
  Construction and borrowing check all original ProducerReads and completion
  availability. The surrounding physical owner must still enforce its current
  scope and resource fence after callbacks and before new physical work.
- Failure: Invalid limits, foreign owner or terminal, missing, duplicate,
  reordered or substituted inputs, wrong operation edges, exhausted graph
  work, or unavailable originals return None. No alternate execution or copied
  relation is constructed.
- Cancellation: This view has no cancellation mechanism or physical close ACK.
  It preserves existing liveness restrictions. Provider cleanup alone does not
  revoke an independently retained completed result; the original owning scope
  supplies the actual lifetime restriction and physical retirement checks.
- Resources: The constructor copies one reference array and allocates one view. The copied array includes its pinned wrapper, backing reference and two scalar words through the shared collection inventory.
  Its construction inventory describes those allocations only; original tuple,
  read, sequence, output, callback and simultaneous borrower lifetimes require
  their own backed inventory before entry. The graph walk is bounded. Quantity
  declarations grant neither resource capacity nor permission.
- Extension: Multiple external ports generalize the existing single-input
  segment bridge without changing CompletedSequence layout or its single-input
  APIs. This is a capability-free borrowed view, not a new nominal authority.
- Verification: completed_segment_inputs_wbtest.mbt uses an actual bounded JOIN
  and checks both ports, values, complete inventory, caller-array mutation,
  same-binding substituted read, foreign same-shape owner, work limits,
  readmission preservation and explicit lifetime refusal. Focused execution
  tests establish neither installed funding nor Source/Content/Model/Effect
  integration, native artifacts, publication or release acceptance.
