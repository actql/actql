///|
/// Observe the original stopped frame before its physical issuer retires the
/// allocator context. A transferred Request admission is deliberately not
/// needed. True means the same child has a complete quiescent Ledger to report;
/// false means no Ledger was published. Neither result is a physical ACK.
pub fn imported_child_retirement_readiness(
  value : ImportedChildLedger,
) -> Result[Bool, ImportedChildLedgerIssue] {
  match imported_child_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.pending_report is Some(_) {
    return Err(value.pending_report_issue.unwrap_or(Unknown))
  }
  if !value.stop_attempted || !value.origin.stopping {
    return Err(Unavailable)
  }
  if value.stop_outcome is Some(issue) {
    return Err(issue)
  }
  if value.ledger is None {
    // A failed original start may not have published a Ledger. Its physical
    // context still needs actual retirement, but there is no usage to invent
    // or report. Successful same-frame stop above is required even in this case.
    return if !value.taken { Ok(false) } else { Err(InvalidOriginal) }
  }
  if !value.attempted {
    return Err(InvalidOriginal)
  }
  // A failed start can publish its Ledger before take/current refuses. Do
  // not take again, invent an empty report, or discard that partial original.
  guard value.taken && value.ledger is Some(ledger) else {
    return Err(Unavailable)
  }
  match check_imported_child_ledger(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if ledger.usage.uncertain_transfer_bytes != 0L ||
    !continuation_quiescent(ledger) ||
    (ledger.original_inventory is Some(inventory) && inventory.park is Some(_)) {
    return Err(Unavailable)
  }
  Ok(true)
}
