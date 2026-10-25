///|
/// Cleanup-only correspondence for an already taken original child. Stopping
/// forbids new admission but must not prevent retiring its existing holders.
/// This checks provenance/currentness only, not quiescence or a release ACK.
pub fn[P] check_node_preparation_cleanup_original(
  value : NodeManagedRunAdmission[P],
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let child = value.child
  match imported_child_original(child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.cleaned || child.origin.fixed_capacities || !child.taken {
    return Err(Unavailable)
  }
  guard value.ledger is Some(admitted) &&
    physical_equal(admitted, ledger) &&
    child.ledger is Some(original) &&
    physical_equal(original, ledger) &&
    ledger.imported_child is Some(origin) &&
    physical_equal(origin, child.origin) else {
    return Err(ForeignOriginal)
  }
  // Unlike admission, this original check allows the owner's stopping signal;
  // unavailable/foreign imports still fail and no capacity is allocated.
  check_imported_child_ledger(ledger).map_err(issue => Resource(issue))
}
