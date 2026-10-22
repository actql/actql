///|
/// A subset check on the exact already-reserved publication token, not a
/// physical profile or another grant. Complete backend overlap still belongs
/// to its installed supplier. This projects neither bytes nor the Ledger.
pub fn original_model_publication_capacity_covers(
  value : OriginalModelPublicationCapacity,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard value.owner is Some(execution) &&
    value.capacity is Some(capacity) &&
    execution.state.call_scope is Some(scope) &&
    original_model_publication_capacity_current(value, execution, scope) else {
    return false
  }
  @resources.capacity_reservation_covers(
    execution.state.ledger,
    capacity,
    retained_bytes,
    execution_bytes,
  )
}

///|
/// Charge exactly the existing ObservationIssuance metadata step on the same
/// original Ledger. This is not a mapping of Model max_work/KernelStep, row
/// counts or capacity bytes into planning work. No amount or Ledger is exposed.
pub fn charge_original_model_observation_step(
  value : OriginalModelPublicationCapacity,
) -> Result[Unit, ModelExecutionIssue] {
  guard value.owner is Some(execution) &&
    execution.state.call_scope is Some(scope) &&
    original_model_publication_capacity_current(value, execution, scope) else {
    return Err(OutputIdentity)
  }
  if execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) &&
    purpose.publication_planning >= purpose.limits.ledger.planning_work {
    return Err(Ledger(@resources.PlanningLimit))
  }
  let shared = execution.state.original_startup is Some(startup) &&
    startup.shared_mock is Some(_)
  if shared {
    execution.advancing = true
  }
  match @resources.charge_planning(execution.state.ledger, 1) {
    Err(issue) => {
      if shared {
        execution.advancing = false
      }
      Err(Ledger(issue))
    }
    Ok(_) => {
      if execution.state.original_startup is Some(startup) &&
        startup.shared_mock is Some(purpose) {
        purpose.publication_planning += 1
      }
      if shared {
        execution.advancing = false
      }
      Ok(())
    }
  }
}
