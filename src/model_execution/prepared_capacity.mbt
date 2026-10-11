///|
// Internal connection only. A consuming owner must derive all additional live
// retention and concurrent scratch from admitted originals and an installed
// physical profile. This is not a public descriptor, an adopted total formula,
// or permission to keep additional input keys without that derivation.
priv struct PreparedModelCapacity {
  prepared_rows : Int
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
fn reserve_prepared_model_capacity(
  ledger : @resources.Ledger,
  prepared_rows : Int,
  bound : PreparedModelCapacity?,
) -> Result[@resources.CapacityReservation?, ModelExecutionIssue] {
  guard bound is Some(bound) else { return Ok(None) }
  if prepared_rows < 0 ||
    bound.prepared_rows != prepared_rows ||
    bound.retained_bytes <= 0L ||
    bound.execution_bytes < 0L {
    return Err(InvalidLimits)
  }
  @resources.reserve_capacity(
    ledger,
    bound.retained_bytes,
    bound.execution_bytes,
  )
  .map(value => Some(value))
  .map_err(issue => Ledger(issue))
}

///|
fn finish_prepared_model_capacity(
  state : ModelState,
) -> Result[Bool, ModelExecutionIssue] {
  if state.prepared_capacity is Some(reservation) {
    // The caller reaches here only after all original output uses and the
    // bounded physical cleanup have permitted retirement. Failure preserves
    // this exact token. Historical/unknown proof custody is not declared free.
    match @resources.settle_capacity(state.ledger, reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Ledger(issue))
    }
    state.prepared_capacity = None
  }
  Ok(true)
}
