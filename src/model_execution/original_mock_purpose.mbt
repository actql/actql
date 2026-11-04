///|
// A restriction within the existing Model owner, never an operational issuer.
// The legacy private name also holds an installed physical provider purpose.
// The actual Host must supply its same-provider purpose and complete
// same-Run overlap before this record, its references or the input are created.
// Resident None on legacy startup also belongs in the physical recipe.
priv struct OriginalMockPurpose {
  provider : ModelProvider
  limits : ModelExecutionLimits
  mut publication_retained : Int64
  mut publication_execution : Int64
  mut publication_planning : Int
}

///|
/// Composed consumers retain their SAME installed provider and Model ceiling
/// on the original shared Run Ledger. Dedicated startup keeps its exact-Ledger
/// path. The same checked handoff still issues the actual reservation; this
/// connection changes neither physical preflight nor dispatch authorization.
pub fn prepare_original_model_provider_consumer_startup(
  consumer : @publication_host.ClientModelReadConsumer,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  scope : @publication_host.ClientInferCallScope,
  rows : @relation.PreparedInferRows,
  provider : ModelProvider,
  limits : ModelExecutionLimits,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  OriginalModelStartup,
  @publication_host.ClientModelInputCapacityIssue,
] {
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(rows))
  let execution = @publication_host.client_infer_plan_graph_execution_contract(
    plan,
  )
  let provider_matches = match provider.invocation {
    OriginalMock(original) =>
      original_mock_provider_matches(original, provider, task) &&
      @environment.model_mock_execution_matches(
        original.profile.unwrap(),
        original.normalized.unwrap(),
        execution,
      )
    SynchronousFixture(_) | AsynchronousPhysical =>
      provider.provider_id == @environment.model_task_connector(task)
  }
  if !provider_matches ||
    !physical_equal(
      execution,
      @publication_host.client_infer_call_scope_model_execution(scope),
    ) ||
    !valid_original_mock_purpose_limits(limits) ||
    limits.ledger.attempts.to_int64() >
    @environment.model_execution_ceiling(execution, @environment.TotalAttempts) ||
    limits.ledger.transfer_bytes >
    @environment.model_execution_ceiling(execution, @environment.TotalWireBytes) ||
    retained_bytes <= 0L ||
    execution_bytes < 0L ||
    retained_bytes > limits.ledger.retained_bytes ||
    execution_bytes > limits.ledger.execution_bytes {
    return Err(@publication_host.ForeignInput)
  }
  let (ledger, capacity) = match
    @publication_host.handoff_client_model_read_consumer_input_capacity(
      consumer, compiled, definition, plan, scope, rows, retained_bytes, execution_bytes,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Refusal after handoff retains this original consumer's existing capacity;
  // the caller must not re-claim or substitute another startup/Run.
  Ok({
    rows,
    scope: Some(scope),
    ledger,
    capacity,
    retained_bytes,
    execution_bytes,
    shared_mock: Some({
      provider,
      limits,
      publication_retained: 0L,
      publication_execution: 0L,
      publication_planning: 0,
    }),
    used: false,
  })
}

///|
fn valid_original_mock_purpose_limits(limits : ModelExecutionLimits) -> Bool {
  let bound = limits.ledger
  limits.max_items >= 0 &&
  limits.max_work >= 0 &&
  limits.max_request_bytes >= 0L &&
  limits.max_response_bytes >= 0L &&
  limits.max_request_bytes <= 9223372036854775807L - limits.max_response_bytes &&
  bound.planning_work >= 0 &&
  bound.attempts >= 0 &&
  bound.holdings >= 0 &&
  bound.transfer_bytes >= 0L &&
  bound.retained_bytes >= 0L &&
  bound.execution_bytes >= 0L
}

///|
fn original_model_startup_limits_match(
  value : OriginalModelStartup,
  limits : ModelExecutionLimits,
  provider : ModelProvider?,
) -> Bool {
  guard value.shared_mock is Some(purpose) else {
    return @resources.ledger_limits(value.ledger) == limits.ledger
  }
  guard provider is Some(provider) &&
    physical_equal(provider, purpose.provider) &&
    physical_equal(limits, purpose.limits) else {
    return false
  }
  let task = @infer.model_task(@relation.prepared_infer_rows_owner(value.rows))
  let provider_matches = match provider.invocation {
    OriginalMock(original) =>
      original_mock_provider_matches(original, provider, task)
    SynchronousFixture(_) | AsynchronousPhysical =>
      provider.provider_id == @environment.model_task_connector(task)
  }
  if !provider_matches {
    return false
  }
  let parent = @resources.ledger_limits(value.ledger)
  let bound = purpose.limits.ledger
  valid_original_mock_purpose_limits(limits) &&
  parent.planning_work >= bound.planning_work &&
  parent.attempts >= bound.attempts &&
  parent.holdings >= bound.holdings &&
  parent.transfer_bytes >= bound.transfer_bytes &&
  parent.retained_bytes >= bound.retained_bytes &&
  parent.execution_bytes >= bound.execution_bytes
}

///|
// Scan the same existing map, including closed identities for spent attempts.
// The Host covers this bounded scan and its scratch before entering the Model.
// Actual live byte amounts come from the original Resource tokens, not rows,
// alias counts, aggregate Run usage or a second private accounting Ledger.
// This selected implementation creates no Model IO/holding. Closed attempt
// amounts do not acknowledge Source holdings, escaped aliases or physical IO;
// those remain charged/retained by their original owners on the same Run.
fn check_original_mock_capacity(
  state : ModelState,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ModelExecutionIssue] {
  guard state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) else {
    return Ok(())
  }
  let bound = purpose.limits.ledger
  if retained < 0L ||
    execution < 0L ||
    startup.retained_bytes > bound.retained_bytes ||
    startup.execution_bytes > bound.execution_bytes {
    return Err(InvalidLimits)
  }
  let mut available_retained = bound.retained_bytes - startup.retained_bytes
  let mut available_execution = bound.execution_bytes - startup.execution_bytes
  for (_, reservation) in state.reservations {
    let (retention, scratch) = match
      @resources.reservation_capacity_amounts(state.ledger, reservation) {
      Err(issue) => return Err(Ledger(issue))
      Ok(value) => value
    }
    if retention > available_retained {
      return Err(Ledger(@resources.RetentionLimit))
    }
    if scratch > available_execution {
      return Err(Ledger(@resources.ExecutionLimit))
    }
    available_retained -= retention
    available_execution -= scratch
  }
  if purpose.publication_retained > available_retained ||
    retained > available_retained - purpose.publication_retained {
    return Err(Ledger(@resources.RetentionLimit))
  }
  if purpose.publication_execution > available_execution ||
    execution > available_execution - purpose.publication_execution {
    return Err(Ledger(@resources.ExecutionLimit))
  }
  Ok(())
}

///|
fn check_original_mock_attempt_capacity(
  state : ModelState,
  transfer : Int64,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ModelExecutionIssue] {
  guard state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) else {
    return Ok(())
  }
  match
    check_original_mock_attempt_budget(
      purpose.limits.ledger,
      state.reservations.length(),
      state.restored_calls.length(),
      state.unknown_calls.length(),
      transfer,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_original_mock_capacity(state, retained, execution)
}

///|
// An authenticated saved attempt is spent, including Unknown. Reconciliation
// may additionally own a read reservation for that slot; count both duties,
// not their union by row/slot. This restriction issues no resource allowance.
fn check_original_mock_attempt_budget(
  bound : @resources.LedgerLimits,
  reservations : Int,
  restored : Int,
  unknown : Int,
  transfer : Int64,
) -> Result[Unit, ModelExecutionIssue] {
  if reservations < 0 || restored < 0 || unknown < 0 || transfer < 0L {
    return Err(InvalidLimits)
  }
  let mut remaining = bound.attempts
  if reservations > remaining {
    return Err(Ledger(@resources.AttemptLimit))
  }
  remaining -= reservations
  if restored > remaining {
    return Err(Ledger(@resources.AttemptLimit))
  }
  remaining -= restored
  if unknown > remaining {
    return Err(Ledger(@resources.AttemptLimit))
  }
  remaining -= unknown
  if remaining <= 0 {
    return Err(Ledger(@resources.AttemptLimit))
  }
  let total = bound.attempts.to_int64() - remaining.to_int64() + 1L
  if bound.transfer_bytes < 0L || transfer > bound.transfer_bytes / total {
    return Err(Ledger(@resources.TransferLimit))
  }
  Ok(())
}

///|
fn check_original_mock_saved_attempt(
  state : ModelState,
  slot : Int,
) -> Result[Unit, ModelExecutionIssue] {
  guard state.original_startup is Some(startup) &&
    startup.shared_mock is Some(purpose) else {
    return Ok(())
  }
  // The original Journal mask must already identify this as an entered slot.
  // A fresh planned send/reservation cannot be relabelled as saved custody.
  if model_slot_send_eligible(state, slot) || state.reservations.contains(slot) {
    return Err(RequestIdentity)
  }
  check_original_mock_attempt_budget(
    purpose.limits.ledger,
    state.reservations.length(),
    state.restored_calls.length(),
    state.unknown_calls.length(),
    state.limits.max_request_bytes + state.limits.max_response_bytes,
  )
}
