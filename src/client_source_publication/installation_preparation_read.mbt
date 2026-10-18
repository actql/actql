///|
// The installing Host supplies the already funded original pair and loan.
// This capture owns only its preparation transition and borrowed references;
// it issues no Ledger, workspace, installation authority or permission.
pub struct InstallationPreparationRead[T] {
  priv mut original : (
    T,
    @buffers.OriginalWorkspaceRead[T],
    @buffers.WorkspaceLoan,
    @resources.FundedReadConsumer[T],
  )?
  priv retained_bytes : Int64
  priv execution_bytes : Int64
}

///|
// Check the exact pair before claiming. Preparing deliberately disables the
// old Reading/Written borrow: it must never be reopened to recheck this use.
// The supplied simultaneous envelope includes this capture and all its users.
pub fn[T] prepare_installation_preparation_read(
  pair : @buffers.OriginalWorkspaceRead[T],
  origin : T,
  loan : @buffers.WorkspaceLoan,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[InstallationPreparationRead[T], @resources.OriginalReadIssue] {
  let claim = match
    @buffers.borrow_workspace_original_read(pair, origin, loan) {
    Some(value) => value
    None => return Err(@resources.ChangedOriginalState)
  }
  @resources.claim_funded_read_preparation(
    claim, origin, retained_bytes, execution_bytes,
  ).map(consumer => {
    original: Some((origin, pair, loan, consumer)),
    retained_bytes,
    execution_bytes,
  })
}

///|
// Awaited consumers recheck the originally captured loan and consumer, not
// another pair on the same Ledger or replaceable JS fields. This is resource
// availability only; Host/Site/current authority and I/O admission are separate.
pub fn[T] installation_preparation_read_current(
  value : InstallationPreparationRead[T],
  origin : T,
) -> Bool {
  guard value.original is Some((original, _, loan, consumer)) else {
    return false
  }
  physical_equal(original, origin) &&
  !loan.closing &&
  !loan.settled &&
  @resources.funded_read_consumer_available(
    consumer,
    original,
    value.retained_bytes,
    value.execution_bytes,
  )
}

///|
// The same single-use Resource transition precedes the consuming physical
// child. Success supplies neither an Account decision nor permission to send.
pub fn[T] enter_installation_preparation_read(
  value : InstallationPreparationRead[T],
  origin : T,
) -> Result[Unit, @resources.OriginalReadIssue] {
  guard value.original is Some((original, _, _, consumer)) else {
    return Err(@resources.SpentClaim)
  }
  if !physical_equal(original, origin) {
    return Err(@resources.ForeignOrigin)
  }
  if !installation_preparation_read_current(value, origin) {
    return Err(@resources.ChangedOriginalState)
  }
  @resources.enter_funded_read_consumer(
    consumer,
    original,
    value.retained_bytes,
    value.execution_bytes,
  )
}

///|
// The original Host still stops/settles the read and physically closes the
// loan. This only retires their borrowed pair and this capture after those
// independent original ACKs. No caller boolean can acknowledge either duty.
pub fn[T] retire_installation_preparation_read(
  value : InstallationPreparationRead[T],
  origin : T,
) -> Result[Unit, @resources.OriginalReadIssue] {
  guard value.original is Some((original, pair, loan, _)) else {
    return Err(@resources.SpentClaim)
  }
  if !physical_equal(original, origin) {
    return Err(@resources.ForeignOrigin)
  }
  match @buffers.retire_workspace_original_read(pair, original, loan) {
    Err(issue) => Err(issue)
    Ok(_) => {
      value.original = None
      Ok(())
    }
  }
}
