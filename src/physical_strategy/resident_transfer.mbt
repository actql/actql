///|
struct ResidentTransfer {
  table : ResidentTable
  reservation : Reservation
  mut settled : Bool
  mut completed : Bool
}

///|
/// Preparation belongs to the selected next consumer, not an arbitrary table
/// in the same environment. Estimates describe admission envelopes, never a
/// substitute for actual bounded transport and capacity enforcement.
fn selected_resident_import(
  run : CapturedDAG,
  env : ResidentEnvironment,
  producer : Int,
) -> Result[ResidentImportEstimate, RunIssue] {
  guard next_captured_task(run) is Some(task) &&
    run.strategy is Some(revision) &&
    strategy_resident_profile(revision, task) is Some(selected) &&
    env.profile is Some(actual) &&
    physical_equal(selected, actual) else {
    return Err(ForeignCandidate)
  }
  match charge_planning(run.ledger, run.graph.data.length()) {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => ()
  }
  let mut required = false
  for edge in run.graph.data {
    if edge.consumer == task && edge.producer == producer {
      required = true
    }
  }
  if !required {
    return Err(ForeignCandidate)
  }
  guard resident_profile_import(selected, producer) is Some(estimate) else {
    return Err(ForeignCandidate)
  }
  Ok(estimate)
}

///|
/// A single import attempt consumes its own transfer/scratch reservation. The
/// DB reservation is shared, not repeated here. Table capacity is already held.
pub fn begin_resident_transfer(
  run : CapturedDAG,
  table : ResidentTable,
  transfer_bytes : Int64,
  scratch_bytes : Int64,
) -> Result[ResidentTransfer, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if !owns_resident_table(run, table) ||
    table.committed ||
    table.import_started ||
    table.allocation.retiring ||
    !resident_environment_available(run, table.environment) {
    return Err(ForeignCandidate)
  }
  if run.running is Some(_) || table.environment.importing {
    return Err(NotReady)
  }
  if transfer_bytes <= 0L || scratch_bytes <= 0L {
    return Err(Physical(InvalidCharge))
  }
  let selected = match
    selected_resident_import(run, table.environment, table.producer) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if transfer_bytes > selected.transfer_bytes ||
    scratch_bytes > selected.scratch_bytes ||
    table.allocation.bytes != selected.table_bytes {
    return Err(Physical(InvalidCharge))
  }
  let reservation = match
    reserve_attempt(run.ledger, transfer_bytes, 0L, scratch_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  table.environment.importing = true
  table.import_started = true
  Ok({ table, reservation, settled: false, completed: false, })
}

///|
pub fn charge_resident_transfer(
  run : CapturedDAG,
  transfer : ResidentTransfer,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  if !owns_resident_table(run, transfer.table) || transfer.settled {
    return Err(ForeignOwner)
  }
  charge_transfer(run.ledger, transfer.reservation, bytes)
}

///|
/// Confirm task connection/transaction cleanup, never shared DB destruction.
pub fn settle_resident_transfer(
  run : CapturedDAG,
  transfer : ResidentTransfer,
  confirmed : Bool,
) -> Result[Unit, LedgerIssue] {
  if !owns_resident_table(run, transfer.table) {
    return Err(ForeignOwner)
  }
  if transfer.settled {
    return Ok(())
  }
  if !confirmed {
    return mark_cleanup_pending(run.ledger, transfer.reservation)
  }
  match settle_reservation(run.ledger, transfer.reservation) {
    Err(issue) => Err(issue)
    Ok(_) => {
      transfer.settled = true
      transfer.table.environment.importing = false
      Ok(())
    }
  }
}

///|
pub fn complete_resident_transfer(
  run : CapturedDAG,
  transfer : ResidentTransfer,
) -> Result[Unit, RunIssue] {
  if !transfer.settled || transfer.completed {
    return Err(NotReady)
  }
  match confirm_resident_table(run, transfer.table) {
    Err(issue) => Err(issue)
    Ok(_) => {
      transfer.completed = true
      Ok(())
    }
  }
}

///|
/// Failure revokes new computation, but does not acknowledge native cleanup or
/// refund the transfer reservation. Completed imports cannot be retroactively
/// turned into failed attempts by this operation.
pub fn abort_resident_transfer(
  run : CapturedDAG,
  transfer : ResidentTransfer,
) -> Result[Unit, RunIssue] {
  if !owns_resident_table(run, transfer.table) || transfer.completed {
    return Err(ForeignCandidate)
  }
  stop_captured_dag(run)
  Ok(())
}
