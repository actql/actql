///|
/// Fund one next native response BEFORE I/O on the original cleanup-bound
/// reader. Previously charged bytes are never refunded; an unused allowance
/// stays on the same reservation until its actual cleanup/settlement.
pub fn ensure_row_run_response_transfer_capacity(
  value : RowRunResponseBorrow,
  bytes : Int64,
) -> Result[Unit, RowHostIssue] {
  match check_row_run_response_borrow_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.cleanup_state is Bound &&
    value.run.page_charge is None &&
    value.run.physical is Some(physical) &&
    physical.provider_capacity is Some(_) else {
    return Err(InvalidState)
  }
  // Reuse this original borrow's synchronous growth fence. A Resource current
  // callback cannot reenter another send, page charge or workspace mutation.
  value.cleanup_state = GrowingWorkspace
  let result = @resources.ensure_transfer_reservation_capacity(
    physical.ledger,
    physical.reservation,
    bytes,
  )
  value.cleanup_state = Bound
  match result {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => ()
  }
  if value.run.page_charge is Some(_) {
    return Err(InvalidState)
  }
  check_row_run_response_borrow_current(value)
}
