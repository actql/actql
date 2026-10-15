///|
// Closed borrowed pair from the installing original Host/operation. These
// references and issuer/consumer overlap belong to its funded envelope.
// This handle owns neither read settlement nor physical workspace cleanup.
struct OriginalWorkspaceRead[T] {
  priv mut binding : @resources.OriginalReadWorkspaceBinding[T]?
  priv mut loan : WorkspaceLoan?
}

///|
pub fn[T] issue_workspace_original_read(
  claim : @resources.FundedReadClaim[T],
  origin : T,
  loan : WorkspaceLoan,
) -> Result[OriginalWorkspaceRead[T], @resources.OriginalReadIssue] {
  if loan.closing || loan.settled {
    return Err(@resources.CleanupPending)
  }
  @resources.issue_original_read_workspace_binding(
    claim, origin, loan.capacity,
  ).map(binding => { binding: Some(binding), loan: Some(loan), })
}

///|
// Recheck this same original after awaits. Equal DATA or another loan on the
// same Ledger is not the Loan captured by this exact pair.
pub fn[T] borrow_workspace_original_read(
  pair : OriginalWorkspaceRead[T],
  origin : T,
  loan : WorkspaceLoan,
) -> @resources.FundedReadClaim[T]? {
  guard pair.loan is Some(original) && pair.binding is Some(binding) else {
    return None
  }
  if !physical_equal(original, loan) || loan.closing || loan.settled {
    return None
  }
  @resources.borrow_original_read_workspace_claim(binding, origin, loan.capacity)
}

///|
pub fn[T] workspace_original_read_matches(
  pair : OriginalWorkspaceRead[T],
  claim : @resources.FundedReadClaim[T],
  origin : T,
  loan : WorkspaceLoan,
) -> Bool {
  borrow_workspace_original_read(pair, origin, loan)
  .map(original => physical_equal(original, claim))
  .unwrap_or(false)
}

///|
// Single finalization of the borrowed handle only. Physical stop/close ACK,
// read settlement and original Run census finish stay with their Owners.
pub fn[T] retire_workspace_original_read(
  pair : OriginalWorkspaceRead[T],
  origin : T,
  loan : WorkspaceLoan,
) -> Result[Unit, @resources.OriginalReadIssue] {
  guard pair.loan is Some(original) && pair.binding is Some(binding) else {
    return Err(@resources.SpentClaim)
  }
  if !physical_equal(original, loan) {
    return Err(@resources.Resource(@resources.ForeignOwner))
  }
  if !loan.stopped || !loan.cleaned || !loan.settled {
    return Err(@resources.CleanupPending)
  }
  match @resources.retire_original_read_workspace_binding(binding, origin, loan.capacity) {
    Err(issue) => Err(issue)
    Ok(_) => {
      pair.binding = None
      pair.loan = None
      Ok(())
    }
  }
}
