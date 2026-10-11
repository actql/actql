///|
// PRIVATE PROPOSAL: not a normal physical profile or a public startup API.
// Before issuance, the original owner must fund this seven-field record, the
// additional ModelState reference, validation and all simultaneous backend
// allocations. Byte arguments below are reviewed grants, not census estimates.
priv struct OriginalModelStartup {
  rows : @relation.PreparedInferRows
  scope : @publication_host.ClientInferCallScope?
  ledger : @resources.Ledger
  capacity : @resources.CapacityReservation
  retained_bytes : Int64
  execution_bytes : Int64
  mut used : Bool
}

///|
// Production must obtain scope/rows from the current bind_run execution after
// its Identity scan. This private prototype retains no generic-origin shortcut
// and accepts no independently reissued Ledger or quantity aggregate.
fn prepare_original_model_startup(
  read : @publication_host.ClientModelReadPreparation,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  scope : @publication_host.ClientInferCallScope,
  rows : @relation.PreparedInferRows,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[OriginalModelStartup, @publication_host.ClientModelInputCapacityIssue] {
  if retained_bytes <= 0L || execution_bytes < 0L {
    return Err(Read(Resource(@resources.InvalidCharge)))
  }
  let (ledger, capacity) = match @publication_host.handoff_client_model_read_input_capacity(
    read, compiled, definition, plan, scope, rows, retained_bytes, execution_bytes,
  ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    rows,
    scope: Some(scope),
    ledger,
    capacity,
    retained_bytes,
    execution_bytes,
    used: false,
  })
}

///|
fn original_model_startup_matches(
  value : OriginalModelStartup,
  rows : @relation.PreparedInferRows,
  scope : @publication_host.ClientInferCallScope?,
  limits : ModelExecutionLimits,
  quantities : ModelQuantityCapacity?,
) -> Bool {
  !value.used &&
  physical_equal(value.rows, rows) &&
  (match (value.scope, scope) {
    (Some(a), Some(b)) => physical_equal(a, b)
    (None, None) => true // Only whitebox fixtures construct an unscoped token.
    _ => false
  }) &&
  @resources.ledger_limits(value.ledger) == limits.ledger &&
  @resources.quantity_configuration_matches(
    value.ledger, quantities.map(value => value.limits),
  ) &&
  value.retained_bytes > 0L &&
  value.execution_bytes >= 0L &&
  @resources.capacity_reservation_matches(
    value.ledger, value.capacity, value.retained_bytes, value.execution_bytes,
  )
}

///|
// Proposed parent-transition fuel connection only. Child codecs, exports,
// SDK/Store work and pre-start validation still need their own reviewed phase
// connection. A successful parent charge is cumulative on the original Ledger;
// cancellation/cleanup never refund it. No public caller selects this policy.
fn charge_original_model_parent_work(
  state : ModelState,
) -> Result[Unit, ModelExecutionIssue] {
  if state.original_startup is Some(_) {
    @resources.charge_planning(state.ledger, 1).map_err(issue => Ledger(issue))
  } else {
    Ok(())
  }
}
