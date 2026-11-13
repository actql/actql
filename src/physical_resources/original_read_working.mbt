///|
/// Grow the SAME consuming Read reservation before its next
/// constructor. This creates no reservation, attempt, transfer allowance or
/// cleanup owner. Native physical construction/growth must be connected by the
/// original Host; these logical extents alone certify no allocator geometry.
/// Complete retained output, scratch and failed-child coexistence belongs in
/// the selected absolute peak. Smaller later quotes never refund the old peak.
pub fn[T] grow_funded_read_consumer_capacity(
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, OriginalReadIssue] {
  if consumer.claim is Some(claim) && claim.children is Some(_) {
    return grow_original_read_child_capacity(
      claim, consumer, origin, retained_bytes, execution_bytes,
    )
  }
  grow_original_read_capacity(
    consumer, origin, retained_bytes, execution_bytes, false,
  )
}

///|
/// The same singular claimed Read may grow during its original preparation,
/// before the one consuming Execution enters. It remains Preparing after a
/// successful grow; no Enter/handoff or new reservation is issued here.
pub fn[T] grow_funded_read_preparing_capacity(
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, OriginalReadIssue] {
  grow_original_read_capacity(
    consumer, origin, retained_bytes, execution_bytes, true,
  )
}

///|
fn[T] grow_original_read_capacity(
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
  preparing : Bool,
) -> Result[Unit, OriginalReadIssue] {
  guard consumer.claim is Some(claim) else { return Err(SpentClaim) }
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  let phase_matches = if preparing {
    claim.phase is Preparing(current) && physical_equal(current, consumer)
  } else {
    claim.phase is ConsumerStarted(current) && physical_equal(current, consumer)
  }
  if claim.children is Some(_) || !phase_matches {
    return Err(SpentClaim)
  }
  let token = claim.read.reservation
  if retained_bytes < token.retention || execution_bytes < token.execution {
    return Err(Resource(InvalidCharge))
  }
  if !funded_read_snapshot_matches(claim, origin) {
    return Err(ChangedOriginalState)
  }
  // Fence before the one original-current callback. A reentrant stop wins;
  // a nested grow, handoff or physical-settle cannot use the in-flight Read.
  claim.phase = ConsumerGrowing(consumer)
  let ledger = claim.descriptor.ledger
  let current_result = reservation_check(ledger, token)
  if !(claim.phase is ConsumerGrowing(current) &&
    physical_equal(current, consumer)) {
    return Err(CleanupPending)
  }
  if current_result is Err(issue) {
    claim.phase = if preparing {
      Preparing(consumer)
    } else {
      ConsumerStarted(consumer)
    }
    return Err(Resource(issue))
  }
  if !funded_read_snapshot_matches(claim, origin) {
    claim.phase = if preparing {
      Preparing(consumer)
    } else {
      ConsumerStarted(consumer)
    }
    return Err(ChangedOriginalState)
  }
  // No external callback separates the final original fence and mutation.
  // A failed capacity check leaves BOTH snapshots and byte vectors exact.
  let result = resize_capacity_reservation_current(
    ledger,
    claim.read,
    retained_bytes,
    execution_bytes,
  )
  if result is Ok(_) {
    claim.read_state = original_reservation_snapshot(token)
    claim.admitted = original_ledger_snapshot(ledger)
  }
  claim.phase = if preparing {
    Preparing(consumer)
  } else {
    ConsumerStarted(consumer)
  }
  result.map_err(issue => Resource(issue))
}

///|
/// Move only the stopped consumer's immutable cleanup DATA to its enclosing
/// funded control lifetime. The trusted Native caller must already be outside
/// every child allocation scope. Old escaped snapshots remain real aliases;
/// this is neither new admission/current nor a cleanup/resource-return ACK.
pub fn[T] relocate_funded_read_consumer_cleanup_state(
  consumer : FundedReadConsumer[T],
  origin : T,
) -> Result[Unit, OriginalReadIssue] {
  guard consumer.claim is Some(claim) else { return Err(SpentClaim) }
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if claim.children is Some(_) ||
    !(claim.phase is ConsumerStopping(current) &&
    physical_equal(current, consumer)) {
    return Err(CleanupPending)
  }
  let previous_read = claim.read_state
  let previous = claim.admitted
  // Construct every replacement before changing either original reference.
  // Copy stored values, never a fresh current Ledger snapshot or authority.
  let read_state : OriginalReservationSnapshot = {
    serial: previous_read.serial,
    transfer: previous_read.transfer,
    retention: previous_read.retention,
    execution: previous_read.execution,
    open: previous_read.open,
    attempt_reserved: previous_read.attempt_reserved,
    attempt_started: previous_read.attempt_started,
    cleanup_pending: previous_read.cleanup_pending,
    quantities: previous_read.quantities.map(cleanup_quantity_copy),
    uncertain_quantities: previous_read.uncertain_quantities.map(
      cleanup_quantity_copy,
    ),
    observed_quantities: (
      previous_read.observed_quantities.0,
      previous_read.observed_quantities.1,
      previous_read.observed_quantities.2,
    ),
    completed_output: previous_read.completed_output.map(value => {
      (value.0, value.1, value.2)
    }),
  }
  let admitted : OriginalLedgerSnapshot = {
    limits: {
      planning_work: previous.limits.planning_work,
      attempts: previous.limits.attempts,
      holdings: previous.limits.holdings,
      transfer_bytes: previous.limits.transfer_bytes,
      retained_bytes: previous.limits.retained_bytes,
      execution_bytes: previous.limits.execution_bytes,
    },
    usage: cleanup_ledger_usage_copy(previous.usage),
    delegated: (
      previous.delegated.0,
      previous.delegated.1,
      previous.delegated.2,
    ),
    quantity_limits: previous.quantity_limits.map(cleanup_quantity_copy),
    quantities: {
      reserved: cleanup_quantity_copy(previous.quantities.reserved),
      uncertain: cleanup_quantity_copy(previous.quantities.uncertain),
      consumed: cleanup_quantity_copy(previous.quantities.consumed),
    },
    next_capacity_serial: previous.next_capacity_serial,
    next_attempt_serial: previous.next_attempt_serial,
    next_holding_serial: previous.next_holding_serial,
  }
  claim.read_state = read_state
  claim.admitted = admitted
  Ok(())
}
