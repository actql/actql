///|
suberror ProcessCapacityFailure {
  Capacity(@resources.LedgerIssue)
}

///|
/// Explicit physical read attempt, independent of the provisioning attempt.
#export_name("processReadReserve")
pub fn process_read_reserve(
  ledger : @resources.Ledger,
  bytes : Int64,
  scratch : Int64,
) -> @resources.Reservation raise ProcessCapacityFailure {
  if bytes < 0L || scratch <= 0L {
    raise Capacity(@resources.InvalidCharge)
  }
  match @resources.reserve_attempt(ledger, bytes, 0L, scratch) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("processReadCharge")
pub fn process_read_charge(
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
  bytes : Int64,
) -> Unit raise ProcessCapacityFailure {
  match @resources.charge_transfer(ledger, reservation, bytes) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("processLedgerCreate")
pub fn process_ledger_create(
  limits : @resources.LedgerLimits,
) -> @resources.Ledger raise ProcessCapacityFailure {
  match @resources.create_ledger(limits) {
    Ok(ledger) => ledger
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("processLedgerUsage")
pub fn process_ledger_usage(
  ledger : @resources.Ledger,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(ledger)
}

///|
/// One provisioning attempt. This does not count or authorize child Compute
/// attempts, transfer, independent file retention, or logical work.
#export_name("processReserve")
pub fn process_reserve(
  ledger : @resources.Ledger,
  retained : Int64,
  execution : Int64,
) -> @resources.Reservation raise ProcessCapacityFailure {
  if retained < 0L || execution <= 0L {
    raise Capacity(@resources.InvalidCharge)
  }
  match @resources.reserve_attempt(ledger, 0L, retained, execution) {
    Err(issue) => raise Capacity(issue)
    Ok(reservation) => reservation
  }
}

///|
/// Trusted control Host calls only after actual exit or known unstarted failure.
#export_name("processStopped")
pub fn process_stopped(
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
) -> Unit raise ProcessCapacityFailure {
  match @resources.settle_reservation(ledger, reservation) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("processDelegate")
pub fn process_delegate(
  ledger : @resources.Ledger,
  limits : @resources.LedgerLimits,
  retained : Int64,
  execution : Int64,
) -> @resources.ExecutionDelegation raise ProcessCapacityFailure {
  match
    @resources.reserve_execution_delegation(ledger, limits, retained, execution) {
    Ok(value) => value
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("processReportUsage")
pub fn process_report_usage(
  ledger : @resources.Ledger,
  delegation : @resources.ExecutionDelegation,
  usage : @resources.LedgerUsage,
) -> Unit raise ProcessCapacityFailure {
  match @resources.report_execution_delegation(ledger, delegation, usage) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
}

///|
#export_name("processDelegationStopped")
pub fn process_delegation_stopped(
  ledger : @resources.Ledger,
  delegation : @resources.ExecutionDelegation,
  final_usage : @resources.LedgerUsage?,
) -> Unit raise ProcessCapacityFailure {
  match
    @resources.settle_execution_delegation(ledger, delegation, final_usage) {
    Ok(_) => ()
    Err(issue) => raise Capacity(issue)
  }
}
