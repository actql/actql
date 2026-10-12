# Original Resident computation evidence for Review recovery

The Native Review continuation previously saved the Captured Run and Preview
wire but omitted the full original computation Receipt chain. A historical
projection alone cannot reconstruct a physical Review or satisfy final Receipt
admission. The Node completion recovery path preserves that chain explicitly;
its adapter is reference material, not a second Native Owner.

The existing Native capture Owner now retains bounded references to the Run,
invocation, public Result definition and Artifact, Manifest, and computation
Receipt already admitted by `prepare_effect_capture_holding_binding`. Preparing
the first Checkpoint serializes those exact bodies into
`provider.original_computation_wire` of its existing private continuation, after
rechecking the common whole computation chain. The original sealed continuation
byte CID and authenticated Store cover the snapshot. No current value is copied
into an older row, and no Source, Compute, Preview or Receipt is issued again.
The six bodies have one closed snapshot shape and use value-preserving canonical
JSON. Original references are cleared only after physical cleanup and reservation
settlement succeed; failures retain the same responsibility.

Original projection readback admits each saved contract, joins its Run and
invocation to the independently retained context, and rechecks the whole
computation chain with the same original Captured Run and Preview. The known
additional field is allowed; foreign provider fields remain refused. An older
record lacking the snapshot retains only its existing historical projection
scope, not a restored computation or execution permission. A future physical
restoration entry must explicitly reject missing originals, never recreate them.

The existing 262,144-byte continuation limit is unchanged. Expansion that cannot
fit fails before a Checkpoint is sealed or sent. Cleanup and reservation Owners,
public report/ACK domains and shapes, Run lifetime, current authorization, and
production `effect_evidence_read=false` remain unchanged. The added private bytes deliberately
change new continuation and Checkpoint identities; stored originals are never
rewritten to those identities.

Portable encoding/refusal cases are distinct from issued proof. Actual Native
Store/Review caller assertions remain compile-only until the existing physical
window is assigned. This unit supplies original recovery material, not physical
Review/row restoration, public approval, Provider execution, Result or release
acceptance. Final merge target is main after #1473, #1475, and #1478.
