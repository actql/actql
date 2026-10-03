///|
/// Type-erased custody for one immutable Carrier generation. It can issue an
/// exact read-only view for a checked consumer edge or reclaim the generation;
/// it cannot expose, serialize, or relabel the family payload.
struct Material {
  reference : CompletionReference
  prepare_input : (@lower.BoundPrepared, Int, @lower.BoundPrepared) -> ProducerView?
  prepare_operation : (@lower.BoundPrepared, Int, Int, @lower.BoundPrepared) -> ProducerView?
  reclaim : () -> Bool
  snapshot_factory : SnapshotFactory?
  snapshot_claimed : Ref[Bool]
  snapshot_operation : Ref[SnapshotIO?]
  snapshot_cleaned : Ref[Bool]
}

///|
pub fn prepare_material(
  reference : CompletionReference,
  prepare_input : (@lower.BoundPrepared, Int, @lower.BoundPrepared) -> ProducerView?,
  prepare_operation : (@lower.BoundPrepared, Int, Int, @lower.BoundPrepared) -> ProducerView?,
  reclaim : () -> Bool,
  snapshot_factory? : SnapshotFactory? = None,
) -> Result[Material, Issue] {
  if !completion_reference_available(reference) {
    return Err(Unavailable)
  }
  Ok({
    reference,
    prepare_input,
    prepare_operation,
    reclaim,
    snapshot_factory,
    snapshot_claimed: Ref(false),
    snapshot_operation: Ref(None),
    snapshot_cleaned: Ref(false),
  })
}

///|
pub fn material_available(value : Material) -> Bool {
  completion_reference_available(value.reference)
}

///|
pub fn material_kind(value : Material) -> @carrier.Kind {
  completion_reference_kind(value.reference)
}

///|
pub fn material_storage_bytes(value : Material) -> Int64? {
  completion_reference_storage_bytes(value.reference)
}

///|
pub fn material_reference(value : Material) -> CompletionReference {
  value.reference
}

///|
/// Issue a fresh use-site view. Repeated input positions remain distinct even
/// when they refer to the same immutable material generation.
pub fn material_prepare_view(
  value : Material,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
) -> Result[ProducerView, Issue] {
  if !material_available(value) {
    return Err(Unavailable)
  }
  guard (value.prepare_input)(receiver, input_index, expected_producer)
    is Some(view) &&
    producer_view_live(view) &&
    producer_read_reference_matches_input(view.read, receiver, input_index) &&
    producer_read_reference_matches_output(view.read, value.reference) else {
    return Err(Unverified)
  }
  if producer_view_kind(view) != material_kind(value) {
    return Err(WrongCarrier)
  }
  Ok(view)
}

///|
/// Issue a fresh view for one exact checked operation edge. The global step
/// and operation-local input position are both retained; this does not turn an
/// internal Carrier into an author-visible Result.
pub fn material_prepare_operation_view(
  value : Material,
  receiver : @lower.BoundPrepared,
  consumer_step : Int,
  input_index : Int,
  expected_producer : @lower.BoundPrepared,
) -> Result[ProducerView, Issue] {
  if !material_available(value) {
    return Err(Unavailable)
  }
  guard (value.prepare_operation)(
      receiver, consumer_step, input_index, expected_producer,
    )
    is Some(view) &&
    producer_view_live(view) &&
    producer_read_reference_matches_operation_input(
      view.read,
      receiver,
      consumer_step,
      input_index,
    ) &&
    producer_read_reference_matches_output(view.read, value.reference) else {
    return Err(Unverified)
  }
  if producer_view_kind(view) != material_kind(value) {
    return Err(WrongCarrier)
  }
  Ok(view)
}

///|
/// Reclaim the exact generation under family-owned disposal. False preserves
/// cleanup custody for retry or reports that reclamation already completed.
pub fn reclaim_material(value : Material) -> Bool {
  if !value.snapshot_cleaned.val &&
    value.snapshot_operation.val is Some(operation) {
    match (operation.cleanup)() {
      // True confirms complete cleanup, including an already-clean operation.
      // False or an error leaves the same handle available for retry.
      Ok(true) => value.snapshot_cleaned.val = true
      Ok(false) | Err(_) => return false
    }
  }
  (value.reclaim)()
}
