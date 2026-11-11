///|
/// Debit the already reserved provider attempt before physical I/O, including
/// operations which receive zero bytes. This neither dispatches nor authorizes
/// transport. The same reservation's existing latch makes repetition idempotent.
pub fn begin_row_run_response_attempt(
  value : RowRunResponseBorrow,
) -> Result[Unit, RowHostIssue] {
  match check_row_run_response_borrow_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let run = value.run
  guard run.attempt.state is Reading(_) && run.physical is Some(physical) else {
    return Err(InvalidState)
  }
  if !row_provider_cleanup_bound(run) {
    return Err(Evidence(UnverifiedTransport))
  }
  match
    @resources.consume_reserved_attempt(physical.ledger, physical.reservation) {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => ()
  }
  // The original Resource current callback may synchronously revoke this
  // response owner. Keep the debit, but never allow I/O under a stale borrow.
  check_row_run_response_borrow_current(value)
}

///|
/// Append actual received bytes to one outstanding original page ticket.
/// The trusted response owner retains the ordered body and its transport
/// correspondence; this accounting port grants neither permission nor data
/// admission. The final original ticket still has to match the whole document.
pub fn extend_row_run_page_charge(
  run : RowRun,
  charge : RowPageCharge,
  body : Bytes,
) -> Result[Unit, RowHostIssue] {
  guard !run.closed &&
    run.attempt.state is Reading(read) &&
    run.physical is Some(physical) else {
    return Err(InvalidState)
  }
  if !row_provider_cleanup_bound(run) {
    return Err(Evidence(UnverifiedTransport))
  }
  if !physical_equal(charge.owner, run.attempt) {
    abort_row_run(run)
    return Err(Physical(ForeignOwner))
  }
  guard !charge.consumed &&
    run.page_charge is Some(expected) &&
    physical_equal(expected, charge) else {
    abort_row_run(run)
    return Err(Physical(InvalidCharge))
  }
  match
    @resources.charge_transfer(
      physical.ledger,
      physical.reservation,
      body.length().to_int64(),
    ) {
    Ok(_) => ()
    Err(issue) => {
      abort_row_run(run)
      return Err(Physical(issue))
    }
  }
  // Currentness can synchronously abort/close the run and consume this ticket.
  // The successful physical debit stays spent, but no stale ticket is renewed.
  guard !run.closed &&
    run.attempt.state is Reading(current) &&
    physical_equal(current, read) &&
    !charge.consumed &&
    run.page_charge is Some(expected) &&
    physical_equal(expected, charge) else {
    return Err(InvalidState)
  }
  // Both operands are nonnegative and bounded by the signed Int page limit.
  // Test subtraction before addition; oversized actual input remains spent.
  if charge.received_bytes > read.page_limits.max_bytes.to_int64() ||
    body.length().to_int64() >
    read.page_limits.max_bytes.to_int64() - charge.received_bytes {
    abort_row_run(run)
    return Err(Source(InvalidPage))
  }
  charge.received_bytes += body.length().to_int64()
  Ok(())
}
