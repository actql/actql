///|
/// The fixed retiring Run clears this durable heavy holder before returning
/// its original Core borrow. This is not an operation-quiescence proof; the
/// Run must already have fenced new work and finished its operation readers.
/// The remaining admission retains only the original child cleanup receipt.
pub fn[P] release_node_preparation_holder(
  admission : NodeManagedRunAdmission[P],
) -> Result[Bool, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(admission) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard admission.preparation_holder is Some(holder) else {
    return if admission.prepared is None { Ok(false) } else { Err(Unavailable) }
  }
  if !preparation_body_retirement_started(holder) {
    return Err(Unavailable)
  }
  guard admission.prepared is Some(original) &&
    preparation_body_borrow_value(holder) is Some(body) &&
    physical_equal(original, body) else {
    return Err(ForeignOriginal)
  }
  admission.prepared = None
  admission.preparation_holder = None
  return_preparation_body_borrow(holder).map_err(issue => {
    match issue {
      Resource(issue) => ImportedChildLedgerIssue::Resource(issue)
      _ => Unavailable
    }
  })
}

///|
/// Fixed cleanup accounting only. Physical stop/output close and reader
/// quiescence remain separate requirements; this predicate acknowledges none.
pub fn[P] node_preparation_usage_isolated(
  admission : NodeManagedRunAdmission[P],
  ledger : Ledger,
) -> Bool {
  guard check_node_preparation_cleanup_original(admission, ledger) is Ok(_) &&
    admission.preparation_holder is Some(holder) else {
    return false
  }
  preparation_body_usage_isolated(holder, ledger)
}
