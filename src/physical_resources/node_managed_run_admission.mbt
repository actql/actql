///|
/// The fixed selected Node installer prepares this existing imported child
/// under a separately admitted Source/managed-Compute recipe. It is not a
/// Source-only child, numerical profile, permission or another Resource owner.
pub struct NodeManagedRunAdmission[P] {
  priv mut original : NodeManagedRunAdmission[P]?
  priv prepared : P
  priv child : ImportedChildLedger
  priv abort_unpublished : () -> Result[Unit, ImportedChildLedgerIssue]
  priv mut attempted : Bool
  priv mut cleaned : Bool
  priv mut ledger : Ledger?
}

///|
fn[P] prepare_node_managed_run_original(
  child : ImportedChildLedger,
  prepared : P,
  abort_unpublished : () -> Result[Unit, ImportedChildLedgerIssue],
) -> NodeManagedRunAdmission[P] {
  let value : NodeManagedRunAdmission[P] = {
    original: None,
    prepared,
    abort_unpublished,
    child,
    attempted: false,
    cleaned: false,
    ledger: None,
  }
  value.original = Some(value)
  value
}

///|
/// Reachable even when start/take did not return a Run view. The same actual
/// child proves whether a Ledger was published; no caller supplies a usage
/// snapshot or a Boolean claiming that allocations were absent.
pub fn[P] cleanup_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.cleaned {
    return Ok(())
  }
  let child = value.child
  if child.pending_report is Some(_) {
    return match child.pending_report_issue {
      Some(issue) => Err(issue)
      None => Err(Unknown)
    }
  }
  if child.stop_attempted {
    return match child.stop_outcome {
      Some(issue) => Err(issue)
      None => {
        value.cleaned = true
        Ok(())
      }
    }
  }
  match child.ledger {
    Some(ledger) => {
      let usage = ledger_usage(ledger)
      if usage.uncertain_transfer_bytes != 0L ||
        usage.reserved_transfer_bytes != 0L ||
        usage.held_bytes != 0L ||
        usage.reserved_retention_bytes != 0L ||
        usage.reserved_execution_bytes != 0L ||
        ledger.delegated_planning != 0 ||
        ledger.delegated_attempts != 0 ||
        ledger.delegated_holdings != 0 {
        return Err(Unavailable)
      }
      if ledger.original_inventory is Some(inventory) && inventory.park is Some(_) {
        return Err(Resource(ResourceParked))
      }
      match report_imported_child_ledger(child) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match stop_imported_child_ledger(child) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    None => {
      if child.origin.ledger is Some(_) {
        return Err(Unknown)
      }
      // No Core Ledger/reservation could have escaped. Report that distinct
      // original initialization outcome, not fabricated zero Ledger usage.
      // The fixed Root independently retains any external/unknown duties.
      value.attempted = true
      // Latch the same original stop flight before invoking external code.
      // Reentry observes Unknown; an uncertain outcome is never retried as a
      // second mutating abort of this unpublished initialization.
      child.origin.stopping = true
      child.stop_attempted = true
      child.stop_outcome = Some(Unknown)
      match (value.abort_unpublished)() {
        Err(issue) => {
          child.stop_outcome = Some(issue)
          return Err(issue)
        }
        Ok(_) => child.stop_outcome = None
      }
    }
  }
  value.cleaned = true
  Ok(())
}

///|
fn[P] check_node_managed_run_original(
  value : NodeManagedRunAdmission[P],
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
pub fn[P] start_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
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
pub fn[P] check_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
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
/// Keep the opaque checked preparation fixed by the actual Root. Equal CIDs
/// or an independently checked copy cannot replace this original afterwards.
pub fn[P] check_node_managed_run_preparation(
  value : NodeManagedRunAdmission[P],
  prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if physical_equal(value.prepared, prepared) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
/// Report the same retained child's actual Core usage. This cannot acknowledge
/// a response backing, FD, escaped result or another physical duty.
pub fn[P] report_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => Err(issue)
    Ok(_) => report_imported_child_ledger(value.child)
  }
}

///|
/// Logical stop only, including the original partial-failure path. The fixed
/// installer retains all physical and shared-domain duties until their ACKs.
pub fn[P] stop_node_managed_run_admission(
  value : NodeManagedRunAdmission[P],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_original(value) {
    Err(issue) => Err(issue)
    Ok(_) => stop_imported_child_ledger(value.child)
  }
}
