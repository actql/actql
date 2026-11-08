///|
/// The installed native transport reports its existing exact encoded frame
/// length. This is the same RowRun reservation/ticket, not provider evidence.
pub fn charge_native_row_input_response(
  run : RowRun,
  bytes : Int64,
) -> Result[RowPageCharge, RowHostIssue] {
  guard bytes >= 0L &&
    !run.closed &&
    run.configuration is InputConfiguration(_) &&
    run.attempt.state is Reading(read) &&
    run.physical is Some(physical) &&
    run.page_charge is None &&
    row_provider_cleanup_bound(run) else {
    return Err(InvalidState)
  }
  if bytes > read.page_limits.max_bytes.to_int64() {
    return Err(Source(InvalidPage))
  }
  match
    @resources.charge_transfer(physical.ledger, physical.reservation, bytes) {
    Ok(_) => ()
    Err(issue) => {
      abort_row_run(run)
      return Err(Physical(issue))
    }
  }
  guard !run.closed &&
    run.attempt.state is Reading(_) &&
    run.page_charge is None else {
    return Err(InvalidState)
  }
  let charge = { owner: run.attempt, received_bytes: bytes, consumed: false, }
  run.page_charge = Some(charge)
  Ok(charge)
}

///|
/// Native schema/codec selection must name this same original input slot.
pub fn check_native_row_input_original(
  run : RowRun,
  acquisition : RowInputAcquisition,
) -> Result[Unit, RowHostIssue] {
  guard !run.closed &&
    run.configuration is InputConfiguration(original) &&
    physical_equal(original, acquisition) &&
    run.attempt.state is Reading(_) else {
    return Err(Source(ForeignSource))
  }
  Ok(())
}
