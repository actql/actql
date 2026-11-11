///|
// Internal connection only. A consuming owner must derive all additional live
// retention and concurrent scratch from admitted originals and an installed
// physical profile. This is not a public descriptor, an adopted total formula,
// or permission to keep additional input keys without that derivation.
// Private numerical arguments in prepared-row, retained-byte, scratch-byte order.
// This alias is package-private and carries no authority or public constructor.
type PreparedModelCapacity = (Int, Int64, Int64)

///|
fn reserve_prepared_model_capacity(
  ledger : @resources.Ledger,
  prepared_rows : Int,
  bound : PreparedModelCapacity?,
) -> Result[@resources.CapacityReservation?, ModelExecutionIssue] {
  guard bound is Some(bound) else { return Ok(None) }
  let (bound_rows, retained_bytes, execution_bytes) = bound
  if prepared_rows < 0 ||
    bound_rows != prepared_rows ||
    retained_bytes <= 0L ||
    execution_bytes < 0L {
    return Err(InvalidLimits)
  }
  @resources.reserve_capacity(ledger, retained_bytes, execution_bytes)
  .map(value => Some(value))
  .map_err(issue => Ledger(issue))
}

///|
fn finish_prepared_model_capacity(
  state : ModelState,
) -> Result[Bool, ModelExecutionIssue] {
  if state.prepared_capacity is Some(reservation) {
    if state.original_startup is Some(original) &&
      (
        !original.used ||
        !physical_equal(original.ledger, state.ledger) ||
        !physical_equal(original.capacity, reservation)
      ) {
      return Err(RequestIdentity)
    }
    // The caller reaches here only after all original output uses and the
    // bounded physical cleanup have permitted retirement. Failure preserves
    // this exact token. Historical/unknown proof custody is not declared free.
    match @resources.settle_capacity(state.ledger, reservation) {
      Ok(_) => ()
      Err(issue) => return Err(Ledger(issue))
    }
    state.prepared_capacity = None
    state.original_startup = None
  }
  // Only our borrowed installation reference retires here. Do not close the
  // shared Host admission or another Run's live IO/holding duties. A failed
  // original cleanup/capacity settlement above preserves this exact reference.
  if state.prepared_call_set is Some(prepared) {
    prepared.io_access = None
    // The escaped set can still identify its reclaimed owner. The owner no
    // longer needs the reverse edge, which would retain the entire execution.
    state.prepared_call_set = None
  }
  Ok(true)
}
