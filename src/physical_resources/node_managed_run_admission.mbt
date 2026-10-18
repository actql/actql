///|
/// The fixed selected Node installer prepares this existing imported child
/// under a separately admitted Source/managed-Compute recipe. It is not a
/// Source-only child, numerical profile, permission or another Resource owner.
pub struct NodeManagedRunAdmission {
  priv mut original : NodeManagedRunAdmission?
  priv child : ImportedChildLedger
  priv mut attempted : Bool
  priv mut ledger : Ledger?
}

///|
fn prepare_node_managed_run_original(
  child : ImportedChildLedger,
) -> NodeManagedRunAdmission {
  let value : NodeManagedRunAdmission = {
    original: None,
    child,
    attempted: false,
    ledger: None,
  }
  value.original = Some(value)
  value
}

///|
fn check_node_managed_run_original(
  value : NodeManagedRunAdmission,
) -> Result[Unit, ImportedChildLedgerIssue] {
  if value.original is Some(original) && physical_equal(original, value) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
/// Existing typed Host assembly only. Retain the admission before this fallible
/// operation. Take its one original Ledger once, then borrow that exact Ledger
/// for both captured Sources and their managed DAG; never restart on failure.
/// This is not exported as a JavaScript Ledger getter.
pub fn start_node_managed_run_admission(
  value : NodeManagedRunAdmission,
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.attempted {
    return Err(AlreadyConsumed)
  }
  value.attempted = true
  match start_imported_child_ledger(value.child) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let ledger = match take_imported_original_child_ledger(value.child) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  value.ledger = Some(ledger)
  Ok(ledger)
}

///|
/// A caller cannot substitute an equal-limit, sibling or reconstructed Ledger.
/// The original installed port also rechecks currentness and purpose.
pub fn check_node_managed_run_admission(
  value : NodeManagedRunAdmission,
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.ledger is Some(original) && physical_equal(original, ledger) else {
    return Err(ForeignOriginal)
  }
  check_imported_original_child_ledger(value.child, ledger)
}

///|
/// Report the same retained child's actual Core usage. This cannot acknowledge
/// a response backing, FD, escaped result or another physical duty.
pub fn report_node_managed_run_admission(
  value : NodeManagedRunAdmission,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => Err(issue)
    Ok(_) => report_imported_child_ledger(value.child)
  }
}

///|
/// Logical stop only, including the original partial-failure path. The fixed
/// installer retains all physical and shared-domain duties until their ACKs.
pub fn stop_node_managed_run_admission(
  value : NodeManagedRunAdmission,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => Err(issue)
    Ok(_) => stop_imported_child_ledger(value.child)
  }
}
