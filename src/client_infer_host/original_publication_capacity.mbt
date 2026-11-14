///|
fn original_infer_publication_owner_current(active : Execution) -> Bool {
  guard !active.advancing &&
    !active.cancelled &&
    !active.reclaimed &&
    active.phase is Terminal &&
    active.completed is Some(_) &&
    active.rows is Some(_) &&
    active.model is Some(_) &&
    active.call_scope is Some(_) &&
    active.original_preparation is Some(original) &&
    original.startup is Some(_) &&
    original.read is Claimed(consumer) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return false
  }
  @publication_host.client_model_read_consumer_handed_off_current(
    consumer,
    bound.compiled,
    bound.definition,
    plan,
  )
}

///|
/// The existing original Execution supplies its actual Model and CallScope.
/// Call before constructing additional publication state, with a justified
/// installed whole publication envelope. This selects no numerical policy,
/// second Ledger or send authority, and creates no new execution Owner.
pub fn reserve_original_infer_publication_capacity(
  active : Execution,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@model.OriginalModelPublicationCapacity, Issue] {
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  @model.reserve_original_model_publication_capacity(
    active.model.unwrap(),
    active.call_scope.unwrap(),
    retained_bytes,
    execution_bytes,
  ).map_err(issue => Model(issue))
}

///|
/// Continue the same terminal Model/Scope's publication reservation from its
/// actual next constructor demand. The original Read must still be current;
/// no new reservation, Model execution or cleanup authority is issued here.
pub fn grow_original_infer_publication_capacity(
  active : Execution,
  capacity : @model.OriginalModelPublicationCapacity,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, Issue] {
  if !original_infer_publication_owner_current(active) {
    return Err(Model(@model.OutputIdentity))
  }
  @model.grow_original_model_publication_capacity(
    capacity,
    active.model.unwrap(),
    active.call_scope.unwrap(),
    retained_bytes,
    execution_bytes,
  ).map_err(issue => Model(issue))
}

///|
/// Release only after the real publication children and aliases have retired,
/// before parent Model cleanup. The opaque borrow retains the original Model;
/// caller Bool/COMMIT/cancellation is not passed as physical cleanup evidence.
pub fn release_original_infer_publication_capacity(
  value : @model.OriginalModelPublicationCapacity,
) -> Result[Bool, Issue] {
  @model.release_original_model_publication_capacity(value).map_err(issue => {
    Model(issue)
  })
}

///|
/// Closed alias/list construction for the actual retained call inventory.
/// This is quote DATA over the SAME Model/Scope, never another reservation.
/// The caller grows its one original publication borrow before constructing
/// native wrappers, then rechecks this same nominal/current relationship.
pub fn original_infer_capture_inventory_capacity(
  active : Execution,
  capacity : @model.OriginalModelPublicationCapacity,
) -> Result[(Int, Int64, Int64), Issue] {
  guard original_infer_publication_owner_current(active) &&
    active.model is Some(model) &&
    active.call_scope is Some(scope) &&
    @model.original_model_publication_capacity_matches_parent(
      capacity, model, scope,
    ) &&
    @model.original_model_publication_capacity_covers(capacity, 0L, 0L) &&
    active.rows is Some(rows) else {
    return Err(Model(@model.OutputIdentity))
  }
  let count = @relation.prepared_infer_rows_count(rows)
  let slots = count.to_int64()
  // Per call: evaluation wrapper and its frozen/reference alternatives,
  // model-evidence alias, copied alias, Core slot pair and binding aliases.
  // Original request/outcome Strings and trees remain with their Model owner;
  // no new parse/normalization is performed merely to obtain this inventory.
  guard @relation.preparation_array_representation(8L, 6L * slots + 16L, true)
    is Some(arrays) &&
    @relation.preparation_representation_cost({
      record_headers: arrays.record_headers + 4L * slots + 16L,
      reference_slots: arrays.reference_slots + 12L * slots + 32L,
      scalar_words: arrays.scalar_words + 4L * slots + 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @relation.preparation_representation_cost({
      record_headers: 8L,
      reference_slots: 4L * slots + 16L,
      scalar_words: 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(workspace) &&
    @relation.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) else {
    return Err(Model(@model.InvalidLimits))
  }
  Ok((count, retained, execution))
}
