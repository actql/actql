///|
// Read-only capacity observation at this original quiescent Model boundary,
// before a Resource park. It is not an allocation, permit, stable cut or ACK.
// A later park or Model/current change invalidates the original observation.
pub fn original_model_unparked_read_capacity_available(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard !active.advancing &&
    !active.cancelled &&
    !active.reclaimed &&
    active.phase is Model &&
    active.rows is Some(rows) &&
    active.call_scope is Some(call_scope) &&
    active.model is Some(model) &&
    active.original_preparation is Some(original) &&
    original.read is Claimed(consumer) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) &&
    @model.model_original_park_candidate(model, rows, call_scope) is Some(_) else {
    return false
  }
  @publication_host.client_model_handed_off_read_capacity_available(
    scope,
    consumer,
    bound.compiled,
    bound.definition,
    plan,
    retained_bytes,
    execution_bytes,
  )
}
