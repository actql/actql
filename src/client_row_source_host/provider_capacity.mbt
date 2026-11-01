///|
// Checked simultaneous overlap, not a physical measurement or a permission.
fn row_provider_capacity_sum(
  retained : Int64,
  execution : Int64,
  scratch : Int64,
  declaration : @execution.ExecutionCapacity?,
) -> Result[(Int64, Int64), RowHostIssue] {
  guard declaration is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  let provider_retained = @execution.execution_capacity_retained_bytes(capacity)
  let provider_execution = @execution.execution_capacity_execution_bytes(
    capacity,
  )
  if retained < 0L ||
    execution < 0L ||
    scratch < 0L ||
    provider_retained < 0L ||
    provider_execution < provider_retained ||
    provider_retained > 9223372036854775807L - retained ||
    provider_execution > 9223372036854775807L - execution {
    return Err(Physical(InvalidLimits))
  }
  let total_execution = execution + provider_execution
  if scratch > 9223372036854775807L - total_execution {
    return Err(Physical(InvalidLimits))
  }
  Ok((retained + provider_retained, total_execution + scratch))
}

///|
/// Pure same-acquisition declaration projection for the existing installed
/// Ledger planner. Neither a reservation nor physical transport admission.
pub fn row_acquisition_provider_capacity(
  value : RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  // This ordinary provider profile does not silently select or supplement a
  // listing-report profile. Those entries keep their original explicit API.
  if row_acquisition_is_listing(value) {
    return None
  }
  match
    row_provider_capacity_sum(
      row_acquisition_retained_capacity(value),
      row_acquisition_execution_capacity(value),
      0L,
      declaration,
    ) {
    Ok((retained, execution)) =>
      @execution.execution_capacity(retained, execution)
    Err(_) => None
  }
}

///|
/// Trusted installation declaration for this original acquisition/reader and
/// target recipe only. Missing or unjustified capacity is unavailable, not a
/// default. ExecutionCapacity is neither an issuer nor an actual reservation.
/// This entry reserves the complete overlap on the supplied original Ledger
/// before constructing the attempt. It does not select listing reports.
pub fn start_accounted_provider_row_acquisition(
  value : RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
  nonce : String,
  verify : (RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
) -> Result[RowRun, RowHostIssue] {
  if transfer_bytes < 0L || execution_scratch < 0L {
    return Err(Physical(InvalidLimits))
  }
  guard row_acquisition_provider_capacity(value, declaration) is Some(capacity) else {
    return Err(Physical(InvalidLimits))
  }
  let retained = @execution.execution_capacity_retained_bytes(capacity)
  let executing = @execution.execution_capacity_execution_bytes(capacity)
  if execution_scratch > 9223372036854775807L - executing {
    return Err(Physical(InvalidLimits))
  }
  let execution = executing + execution_scratch
  let reservation = match
    @resources.reserve_attempt(
      ledger,
      transfer_bytes,
      retained,
      execution,
      quantities=@resources.quantity_neutral_amounts(ledger),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  let run = match start_row_acquisition(value, nonce, verify) {
    Ok(value) => value
    Err(issue) =>
      match @resources.settle_reservation(ledger, reservation) {
        Ok(_) => return Err(issue)
        Err(resource_issue) => return Err(Physical(resource_issue))
      }
  }
  install_row_reservation(
    run,
    ledger,
    reservation,
    execution_scratch,
    provider_capacity=declaration,
  )
  Ok(run)
}

///|
// Admission cannot precede the original reader's one-shot cleanup binding.
// This checks installation of the observer, not its current stopped value:
// rows may complete while diagnostics/backing remain physically retained.
fn row_provider_cleanup_bound(run : RowRun) -> Bool {
  match run.physical {
    Some(physical) =>
      physical.provider_capacity is None ||
      (run.response_borrowed && physical.cleanup_confirmed is Some(_))
    None => true
  }
}
