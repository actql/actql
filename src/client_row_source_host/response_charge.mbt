///|
/// Consume the same-run charge for a bounded non-row protocol response.
/// This acknowledges byte-ticket consumption only: it appends no row, finishes
/// no scan, issues no evidence and does not confirm physical transport cleanup.
pub fn consume_row_run_response_charge(
  run : RowRun,
  charge : RowPageCharge,
) -> Result[Unit, RowHostIssue] {
  consume_row_page_charge(run, charge)
}

///|
/// Account for an original received native protocol body under the SAME
/// cleanup-bound provider reader. Its selected physical transfer reservation
/// bounds these bytes; the row JSON page bound is checked separately when the
/// projected data page is admitted. This creates no row or physical ACK and
/// never charges an announced length or an encoding of projected rows.
pub fn charge_row_run_response_body(
  run : RowRun,
  body : Bytes,
) -> Result[RowPageCharge, RowHostIssue] {
  guard !run.closed &&
    run.attempt.state is Reading(_) &&
    run.physical is Some(physical) &&
    physical.provider_capacity is Some(_) else {
    return Err(InvalidState)
  }
  if !row_provider_cleanup_bound(run) {
    return Err(Evidence(UnverifiedTransport))
  }
  if run.page_charge is Some(_) {
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
  let charge = {
    owner: run.attempt,
    received_bytes: body.length().to_int64(),
    consumed: false,
  }
  run.page_charge = Some(charge)
  Ok(charge)
}
