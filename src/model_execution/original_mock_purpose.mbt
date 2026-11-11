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
  // These are the SAME component ceilings retained by the original seal,
  // not an allocation of every maximum on the shared parent. Component work,
  // attempt/response/quantity admission still checks this exact Limits value;
  // Resource independently admits each actual operation against the SAME
  // parent's aggregate limits and consumed history. Neither ceiling is raised.
  valid_original_mock_purpose_limits(limits)
}

///|
// Scan the same existing map, including closed identities for spent attempts.
// The Host covers this bounded scan and its scratch before entering the Model.
// Actual live byte amounts come from the original Resource tokens, not rows,
// alias counts, aggregate Run usage or a second private accounting Ledger.
// This selected implementation creates no Model IO/holding. Closed attempt
// amounts do not acknowledge Source holdings, escaped aliases or physical IO;
// those remain charged/retained by their original owners on the same Run.
// The attempt entrance folds component quantity checks into this SAME scan.
// Actual trace observations replace their uncertain envelopes; saved-only
// proofs add no quantity charge. No count-times-worst-case fee or counter is
// reconstructed, and undispatched settled quantities are not spent usage.
fn check_original_mock_capacity(
  state : ModelState,
  retained : Int64,
  execution : Int64,
  reserve_quantities? : Bool = false,
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
  let quantities = if reserve_quantities {
    state.quantity_capacity
  } else {
    None
  }
  let mut tokens = match quantities {
    None => 0L
    Some(value) => value.limits.tokens
  }
  let mut cost = match quantities {
    None => 0L
    Some(value) => value.limits.cost_units
  }
  let mut duration = match quantities {
    None => 0L
    Some(value) => value.limits.duration_ms
  }
  if quantities is Some(value) &&
    (
      tokens < 0L ||
      cost < 0L ||
      duration < 0L ||
      value.per_attempt.tokens < 0L ||
      value.per_attempt.cost_units < 0L ||
      value.per_attempt.duration_ms < 0L
    ) {
    return Err(InvalidLimits)
  }
  for (slot, reservation) in state.reservations {
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
    if quantities is Some(_) {
      let (reserved, uncertain, observed) = match
        @resources.reservation_quantity_state(state.ledger, reservation) {
        Err(issue) => return Err(Ledger(issue))
        Ok(value) => value
      }
      // These are the original token's retained amounts, including after close.
      for index in 0..<2 {
        let amount = if index == 0 { reserved } else { uncertain }
        if amount is Some(amount) {
          if amount.tokens > tokens {
            return Err(Ledger(@resources.TokenLimit))
          }
          if amount.cost_units > cost {
            return Err(Ledger(@resources.CostLimit))
          }
          if amount.duration_ms > duration {
            return Err(Ledger(@resources.DurationLimit))
          }
          tokens -= amount.tokens
          cost -= amount.cost_units
          duration -= amount.duration_ms
        }
      }
      // Model currently observes tokens only; cost/duration stay uncertain.
      // Never infer a missing observation from a closed token or a response name.
      if observed.1 || observed.2 {
        return Err(RequestIdentity)
      }
      if observed.0 {
        guard state.attempts.get(slot) is Some(trace) &&
          trace.input_tokens is Some(input) &&
          input >= 0L &&
          trace.output_tokens is Some(output) &&
          output >= 0L else {
          return Err(RequestIdentity)
        }
        if input > tokens {
          return Err(Ledger(@resources.TokenLimit))
        }
        tokens -= input
        if output > tokens {
          return Err(Ledger(@resources.TokenLimit))
        }
        tokens -= output
      }
    }
  }
  // Original publication borrows are already charged by this SAME parent
  // Ledger. They are not a second Model attempt/output allocation and cannot
  // shrink or enlarge this component's Model work ceiling. Their separate
  // counters retain original cleanup association, not another byte quota.
  if retained > available_retained {
    return Err(Ledger(@resources.RetentionLimit))
  }
  if execution > available_execution {
    return Err(Ledger(@resources.ExecutionLimit))
  }
  if quantities is Some(value) {
    let next = value.per_attempt
    if next.tokens > tokens {
      return Err(Ledger(@resources.TokenLimit))
    }
    if next.cost_units > cost {
      return Err(Ledger(@resources.CostLimit))
    }
    if next.duration_ms > duration {
      return Err(Ledger(@resources.DurationLimit))
    }
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
  check_original_mock_capacity(
    state,
    retained,
    execution,
    reserve_quantities=true,
  )
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
