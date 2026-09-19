///|
/// Carrier-specific finite measurements attached to one completed material.
/// These are physical and logical extent facts, not content identities.
pub(all) enum Measure {
  RelationMeasure(rows~ : Int, columns~ : Int)
  GraphMeasure(nodes~ : Int, edges~ : Int)
  EventsMeasure(records~ : Int)
  VectorsMeasure(records~ : Int, dimensions~ : Int)
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  MissingCarrier
  WrongCarrier
  InvalidMeasure
  Closed
  ForeignReceipt
  InvalidStorageBytes
  Unavailable
  Unverified
} derive(Eq, Debug)

///|
/// Exact semantic output binding established before execution. It is neither a
/// content identity nor permission to read material.
struct Binding {
  identity : Ref[Unit]
  owner : @lower.BoundPrepared
  target : @pipeline.Target
  carrier : @carrier.Carrier
}

///|
/// Finite output facts for the exact binding. Carrier kinds retain distinct
/// measures rather than forcing every output through Relation row semantics.
struct Receipt {
  binding : Binding
  measure : Measure
}

///|
struct RetentionPort[P, E, T] {
  binding : Binding
  verify : (P) -> (Receipt, E, T, Int64, () -> Bool)?
  mut open : Bool
  mut verifying : Bool
  mut revoked : Bool
}

///|
/// One immutable managed generation. Evidence is retained separately from the
/// payload so Carrier-specific admission can remain typed.
struct Retained[E, T] {
  receipt : Receipt
  evidence : E
  payload : T
  storage_bytes : Int64
  available : () -> Bool
}

///|
/// Common completed occurrence. Higher layers retain attempt, authorization,
/// identity and publication obligations; this value owns only lifecycle state.
struct Completed[E, T] {
  identity : Ref[Unit]
  retained : Retained[E, T]
  mut revoked : Bool
  mut reclaimed : Bool
}

///|
/// Type-erased occurrence reference for scheduling and holding. It is not a
/// serialized handle, content identity or read authorization.
struct CompletionReference {
  identity : Ref[Unit]
  binding : Binding
  storage_bytes : Int64
  available : () -> Bool
}

///|
/// Type-erased proof of one exact receiving use site. It carries no payload
/// access and cannot be converted back into a typed read handle.
struct ProducerReadReference {
  identity : Ref[Unit]
  receiver : @lower.BoundPrepared
  input_index : Int
  consumer_target : @pipeline.Target
  output : CompletionReference
}

///|
/// Exact receiving occurrence for one typed Carrier input. This is a checked
/// use-site binding, not a pin, payload identity, or serialized authority.
struct ProducerRead[E, T] {
  identity : Ref[Unit]
  receiver : @lower.BoundPrepared
  input_index : Int
  consumer_target : @pipeline.Target
  output : Completed[E, T]
}

///|
pub(all) enum ProducerReadIssue {
  InvalidInput
  ProducerOwnerMismatch
  ProducerBindingMismatch
  ProducerTargetMismatch
  ProducerUnavailable
} derive(Eq, Debug)

///|
pub fn prepare_binding(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Result[Binding, Issue] {
  guard @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(carrier) else {
    return Err(MissingCarrier)
  }
  Ok({ identity: Ref(()), owner, target, carrier, })
}

///|
pub fn binding_kind(binding : Binding) -> @carrier.Kind {
  @carrier.kind(binding.carrier)
}

///|
pub fn binding_carrier(binding : Binding) -> @carrier.Carrier {
  binding.carrier
}

///|
pub fn binding_matches(
  binding : Binding,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  physical_equal(binding.owner, owner) && binding.target == target
}

///|
pub fn binding_same(left : Binding, right : Binding) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn complete_receipt(
  binding : Binding,
  measure : Measure,
) -> Result[Receipt, Issue] {
  let valid = match (binding_kind(binding), measure) {
    (@carrier.RelationKind, RelationMeasure(rows~, columns~)) =>
      rows >= 0 && columns >= 0
    (@carrier.GraphKind, GraphMeasure(nodes~, edges~)) =>
      nodes >= 0 && edges >= 0
    (@carrier.EventsKind, EventsMeasure(records~)) => records >= 0
    (@carrier.VectorsKind, VectorsMeasure(records~, dimensions~)) =>
      records >= 0 && dimensions >= 0
    _ => return Err(WrongCarrier)
  }
  if !valid {
    return Err(InvalidMeasure)
  }
  Ok({ binding, measure, })
}

///|
pub fn receipt_measure(receipt : Receipt) -> Measure {
  receipt.measure
}

///|
pub fn receipt_matches_binding(receipt : Receipt, binding : Binding) -> Bool {
  binding_same(receipt.binding, binding)
}

///|
pub fn receipt_matches(
  receipt : Receipt,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  binding_matches(receipt.binding, owner, target)
}

///|
/// Install trusted verification before execution. Issuance is consumed before
/// trusted code runs, so failure cannot be retried into another generation.
pub fn[P, E, T] prepare_retention_port(
  binding : Binding,
  verify : (P) -> (Receipt, E, T, Int64, () -> Bool)?,
) -> RetentionPort[P, E, T] {
  { binding, verify, open: true, verifying: false, revoked: false, }
}

///|
pub fn[P, E, T] cancel_retention_port(port : RetentionPort[P, E, T]) -> Bool {
  if port.revoked || (!port.open && !port.verifying) {
    return false
  }
  port.open = false
  port.revoked = true
  true
}

///|
pub fn[P, E, T] retain(
  port : RetentionPort[P, E, T],
  proof : P,
) -> Result[Retained[E, T], Issue] {
  if !port.open {
    return Err(Closed)
  }
  port.open = false
  port.verifying = true
  let verified = (port.verify)(proof)
  port.verifying = false
  if port.revoked {
    return Err(Closed)
  }
  guard verified is Some((receipt, evidence, payload, bytes, available)) else {
    return Err(Unverified)
  }
  if !receipt_matches_binding(receipt, port.binding) {
    return Err(ForeignReceipt)
  }
  if bytes < 0L {
    return Err(InvalidStorageBytes)
  }
  port.verifying = true
  let live = available()
  port.verifying = false
  if port.revoked {
    return Err(Closed)
  }
  if !live {
    return Err(Unavailable)
  }
  Ok({ receipt, evidence, payload, storage_bytes: bytes, available, })
}

///|
pub fn[E, T] retained_receipt(value : Retained[E, T]) -> Receipt {
  value.receipt
}

///|
pub fn[E, T] retained_evidence(value : Retained[E, T]) -> E {
  value.evidence
}

///|
pub fn[E, T] retained_available(value : Retained[E, T]) -> Bool {
  (value.available)()
}

///|
pub fn[E, T] retained_payload(value : Retained[E, T]) -> T? {
  if retained_available(value) {
    Some(value.payload)
  } else {
    None
  }
}

///|
pub fn[E, T] retained_storage_bytes(value : Retained[E, T]) -> Int64? {
  if retained_available(value) {
    Some(value.storage_bytes)
  } else {
    None
  }
}

///|
pub fn[E, T] complete(
  retained : Retained[E, T],
) -> Result[Completed[E, T], Issue] {
  if !retained_available(retained) {
    return Err(Unavailable)
  }
  Ok({ identity: Ref(()), retained, revoked: false, reclaimed: false, })
}

///|
pub fn[E, T] completed_available(value : Completed[E, T]) -> Bool {
  !value.revoked && !value.reclaimed && retained_available(value.retained)
}

///|
/// Revoke an unpublished completed generation before disposing its payload.
/// Historical occurrence identity remains distinct from current availability.
pub fn[E, T] revoke_completed(value : Completed[E, T]) -> Bool {
  if value.revoked {
    false
  } else {
    value.revoked = true
    true
  }
}

///|
/// Reclaim an unpublished completed payload under its retained ownership.
/// Current read availability is deliberately irrelevant: revocation closes
/// use authority, but must not erase the owner's cleanup responsibility.
pub fn[E, T] reclaim_completed(
  value : Completed[E, T],
  dispose : (T) -> Bool,
) -> Bool {
  if value.reclaimed {
    return false
  }
  value.revoked = true
  if dispose(value.retained.payload) {
    value.reclaimed = true
    true
  } else {
    false
  }
}

///|
pub fn[E, T] completed_measure(value : Completed[E, T]) -> Measure {
  receipt_measure(value.retained.receipt)
}

///|
pub fn[E, T] completed_evidence(value : Completed[E, T]) -> E? {
  if completed_available(value) {
    Some(value.retained.evidence)
  } else {
    None
  }
}

///|
pub fn[E, T] completed_payload(value : Completed[E, T]) -> T? {
  if completed_available(value) {
    Some(value.retained.payload)
  } else {
    None
  }
}

///|
pub fn[E, T] completed_storage_bytes(value : Completed[E, T]) -> Int64? {
  if completed_available(value) {
    Some(value.retained.storage_bytes)
  } else {
    None
  }
}

///|
pub fn[E, T] completion_reference(
  value : Completed[E, T],
) -> CompletionReference {
  {
    identity: value.identity,
    binding: value.retained.receipt.binding,
    storage_bytes: value.retained.storage_bytes,
    available: fn() { completed_available(value) },
  }
}

///|
pub fn completion_reference_available(value : CompletionReference) -> Bool {
  (value.available)()
}

///|
pub fn completion_reference_same(
  left : CompletionReference,
  right : CompletionReference,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn completion_reference_kind(value : CompletionReference) -> @carrier.Kind {
  binding_kind(value.binding)
}

///|
pub fn completion_reference_matches_port(
  value : CompletionReference,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  binding_matches(value.binding, owner, target) &&
  completion_reference_available(value)
}

///|
pub fn completion_reference_storage_bytes(
  value : CompletionReference,
) -> Int64? {
  if completion_reference_available(value) {
    Some(value.storage_bytes)
  } else {
    None
  }
}

///|
pub fn[E, T] completion_reference_matches(
  reference : CompletionReference,
  value : Completed[E, T],
) -> Bool {
  physical_equal(reference.identity, value.identity) &&
  completion_reference_available(reference) &&
  completed_available(value)
}

///|
/// Bind a completed Carrier generation to the exact checked producer edge.
/// Equal payloads, contracts, or CIDs cannot substitute another invocation.
pub fn[E, T] prepare_producer_read(
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
  output : Completed[E, T],
) -> Result[ProducerRead[E, T], ProducerReadIssue] {
  if !completed_available(output) {
    return Err(ProducerUnavailable)
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(receiver))
  guard @pipeline.input_producer(pipeline, input_index) is Some(producer) else {
    return Err(InvalidInput)
  }
  if !physical_equal(
      @pipeline.producer_pipeline(producer),
      @lower.pipeline(@lower.bound_preparation(expected_producer)),
    ) {
    return Err(ProducerOwnerMismatch)
  }
  let binding = output.retained.receipt.binding
  if !physical_equal(binding.owner, expected_producer) {
    return Err(ProducerBindingMismatch)
  }
  if binding.target != @pipeline.producer_target(producer) {
    return Err(ProducerTargetMismatch)
  }
  if !completed_available(output) {
    return Err(ProducerUnavailable)
  }
  Ok({
    identity: Ref(()),
    receiver,
    input_index,
    consumer_target: @pipeline.Input(input_index),
    output,
  })
}

///|
/// Bind one immutable Carrier generation to an exact edge between two steps
/// in the same checked sequence. This is not an external pipeline input and
/// cannot be substituted for one merely because its position is also zero.
pub fn[E, T] prepare_step_producer_read(
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
  output : Completed[E, T],
) -> Result[ProducerRead[E, T], ProducerReadIssue] {
  if !completed_available(output) {
    return Err(ProducerUnavailable)
  }
  let prepared = @lower.bound_preparation(receiver)
  guard @lower.node_at(prepared, consumer_step) is Some(node) &&
    @lower.node_input_target(node, input_index) is Some(producer_target) else {
    return Err(InvalidInput)
  }
  let binding = output.retained.receipt.binding
  if !physical_equal(binding.owner, receiver) {
    return Err(ProducerOwnerMismatch)
  }
  if binding.target != producer_target {
    return Err(ProducerTargetMismatch)
  }
  if !completed_available(output) {
    return Err(ProducerUnavailable)
  }
  Ok({
    identity: Ref(()),
    receiver,
    input_index,
    consumer_target: @pipeline.Step(consumer_step),
    output,
  })
}

///|
pub fn[E, T] producer_read_available(value : ProducerRead[E, T]) -> Bool {
  completed_available(value.output)
}

///|
pub fn[E, T] producer_read_receiver(
  value : ProducerRead[E, T],
) -> @lower.BoundPrepared {
  value.receiver
}

///|
pub fn[E, T] producer_read_input_index(value : ProducerRead[E, T]) -> Int {
  value.input_index
}

///|
pub fn[E, T] producer_read_consumer_target(
  value : ProducerRead[E, T],
) -> @pipeline.Target {
  value.consumer_target
}

///|
pub fn[E, T] producer_read_same(
  left : ProducerRead[E, T],
  right : ProducerRead[E, T],
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
/// Installed Host lookup only. Dispatch still acquires its own use authority,
/// physical reservation, and retention before dereferencing this payload.
pub fn[E, T] producer_read_payload(value : ProducerRead[E, T]) -> T? {
  if producer_read_available(value) {
    retained_payload(value.output.retained)
  } else {
    None
  }
}

///|
pub fn[E, T] producer_read_matches_reference(
  value : ProducerRead[E, T],
  reference : CompletionReference,
) -> Bool {
  completion_reference_matches(reference, value.output) &&
  producer_read_available(value)
}

///|
pub fn[E, T] producer_read_reference(
  value : ProducerRead[E, T],
) -> ProducerReadReference {
  {
    identity: value.identity,
    receiver: value.receiver,
    input_index: value.input_index,
    consumer_target: value.consumer_target,
    output: completion_reference(value.output),
  }
}

///|
pub fn producer_read_reference_available(value : ProducerReadReference) -> Bool {
  completion_reference_available(value.output)
}

///|
pub fn producer_read_reference_same(
  left : ProducerReadReference,
  right : ProducerReadReference,
) -> Bool {
  physical_equal(left.identity, right.identity)
}

///|
pub fn producer_read_reference_matches_input(
  value : ProducerReadReference,
  receiver : @lower.BoundPrepared,
  input_index : Int,
) -> Bool {
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  value.consumer_target == @pipeline.Input(input_index) &&
  producer_read_reference_available(value)
}

///|
pub fn producer_read_reference_matches_step(
  value : ProducerReadReference,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
) -> Bool {
  physical_equal(value.receiver, receiver) &&
  value.input_index == input_index &&
  value.consumer_target == @pipeline.Step(consumer_step) &&
  producer_read_reference_available(value)
}

///|
/// Match the read against one exact operation input. External pipeline reads
/// retain their Input target; internal reads retain the consuming Step.
pub fn producer_read_reference_matches_operation_input(
  value : ProducerReadReference,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  edge_index : Int,
) -> Bool {
  if !physical_equal(value.receiver, receiver) ||
    !producer_read_reference_available(value) {
    return false
  }
  let prepared = @lower.bound_preparation(receiver)
  guard @lower.node_at(prepared, consumer_step) is Some(node) &&
    @lower.node_input_target(node, edge_index) is Some(source) else {
    return false
  }
  match value.consumer_target {
    @pipeline.Input(index) =>
      value.input_index == index && source == @pipeline.Input(index)
    @pipeline.Step(step) =>
      value.input_index == edge_index && step == consumer_step
  }
}

///|
pub fn producer_read_reference_matches_output(
  value : ProducerReadReference,
  output : CompletionReference,
) -> Bool {
  completion_reference_same(value.output, output) &&
  producer_read_reference_available(value)
}
