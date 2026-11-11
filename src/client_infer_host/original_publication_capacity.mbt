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
