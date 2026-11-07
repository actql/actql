///|
// Same Resource-owned transfer for Node and backed imported preparation.
// Both public callers capture their actual original before this private
// synchronous boundary. No caller-supplied current callback is admitted.
fn[I, P] transfer_preparation_adoption_holders(
  capacity : PreparationCapacity[I, P],
  input : I,
  prepared : P,
  ledger : Ledger,
  observe_current : () -> Result[Unit, ImportedChildLedgerIssue],
) -> Result[
  (PreparationRetirement, PreparationBodyBorrow[P], PreparationBodyBorrow[P]),
  ImportedChildLedgerIssue,
] {
  capacity.phase = Transferring
  capacity.borrowers += 2
  let current = observe_current()
  let transferred : Result[PreparationRetirement, ImportedChildLedgerIssue] = match
    current {
    Err(issue) => Err(issue)
    Ok(_) =>
      match
        finish_preparation_capacity_run_current(
          capacity, input, prepared, ledger,
        ) {
        Err(ForeignOriginal) => Err(ForeignOriginal)
        Err(Resource(issue)) => Err(Resource(issue))
        Err(_) => Err(Unavailable)
        Ok(_) =>
          match claim_preparation_run_retirement(capacity) {
            Err(Resource(issue)) => Err(Resource(issue))
            Err(_) => Err(Unavailable)
            Ok(retirement) => Ok(retirement)
          }
      }
  }
  let retirement = match transferred {
    Err(issue) => {
      capacity.borrowers -= 2
      capacity.phase = Ready
      return Err(issue)
    }
    Ok(value) => value
  }
  let holder = make_preparation_body_borrow({
    owner: capacity,
    body: Some(prepared),
    returned: false,
  })
  let run_holder = make_preparation_body_borrow({
    owner: capacity,
    body: Some(prepared),
    returned: false,
  })
  Ok((retirement, holder, run_holder))
}
