///|
/// The fixed selected Node installer prepares this existing imported child
/// under a separately admitted Source/managed-Compute recipe. It is not a
/// Source-only child, numerical profile, permission or another Resource owner.
priv enum NodeManagedRunPurpose {
  SourceCompute
  LocalMockModel
  LocalContent
}

///|
pub struct NodeManagedRunAdmission[P] {
  priv mut original : NodeManagedRunAdmission[P]?
  priv mut prepared : P?
  priv purpose : NodeManagedRunPurpose
  priv child : ImportedChildLedger
  priv abort_unpublished : () -> Result[Unit, ImportedChildLedgerIssue]
  priv mut attempted : Bool
  priv mut cleaned : Bool
  priv mut ledger : Ledger?
  // Resident even when absent. The selected same-Run envelope includes this
  // early custody before any read-scope constructor or ordinary child token.
  priv mut read_bootstrap_attempted : Bool
  priv mut read_bootstrap : CapacityReservation?
}

///|
fn[P] prepare_node_managed_run_original(
  child : ImportedChildLedger,
  prepared : P,
  abort_unpublished : () -> Result[Unit, ImportedChildLedgerIssue],
  purpose? : NodeManagedRunPurpose = SourceCompute,
) -> NodeManagedRunAdmission[P] {
  let value : NodeManagedRunAdmission[P] = {
    original: None,
    prepared: Some(prepared),
    purpose,
    abort_unpublished,
    child,
    attempted: false,
    cleaned: false,
    ledger: None,
    read_bootstrap_attempted: false,
    read_bootstrap: None,
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
        value.prepared = None
        value.cleaned = true
        Ok(())
      }
    }
  }
  match child.ledger {
    Some(ledger) => {
      match cleanup_node_managed_run_read_bootstrap(value, ledger) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
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
      if ledger.original_inventory is Some(inventory) &&
        inventory.park is Some(_) {
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
  value.prepared = None
  value.cleaned = true
  Ok(())
}

///|
/// Reserve only from this already admitted original Run. This charges its
/// existing capacity; it issues no Model purpose, physical supplier or second
/// Ledger. The fixed Host must have selected that separate purpose first.
/// Retain the token before the fallible post-current/scope-constructor steps,
/// so the original admission also owns their partial-initialization cleanup.
pub fn[P] reserve_node_managed_run_read_bootstrap(
  value : NodeManagedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[CapacityReservation, ImportedChildLedgerIssue] {
  match check_node_managed_run_preparation(value, prepared) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.cleaned || value.read_bootstrap_attempted {
    return Err(AlreadyConsumed)
  }
  guard value.ledger is Some(original) && physical_equal(original, ledger) else {
    return Err(ForeignOriginal)
  }
  // Latch before invoking original currentness. Reentry or a failed attempt
  // cannot install a replacement bootstrap or retrospectively census a child.
  value.read_bootstrap_attempted = true
  match check_node_managed_run_admission(value, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if retained_bytes <= 0L ||
    execution_bytes <= 0L ||
    ledger.next_capacity_serial != Some(-1) ||
    ledger.original_inventory is Some(_) ||
    !original_ledger_has_no_child_usage(ledger, 0L, 0L) {
    return Err(Resource(InvalidCharge))
  }
  let bootstrap = match
    reserve_capacity(ledger, retained_bytes, execution_bytes) {
    Err(issue) => return Err(Resource(issue))
    Ok(token) => token
  }
  value.read_bootstrap = Some(bootstrap)
  // The existing census predicate includes attempts, zero-byte identities,
  // quantities and delegated children. Never weaken it to equal usage bytes.
  if !original_ledger_has_only_bootstrap(ledger, bootstrap) {
    return Err(Unavailable)
  }
  match check_node_managed_run_admission(value, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => Ok(bootstrap)
  }
}

///|
fn[P] cleanup_node_managed_run_read_bootstrap(
  value : NodeManagedRunAdmission[P],
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  guard value.read_bootstrap is Some(bootstrap) else { return Ok(()) }
  if !physical_equal(bootstrap.reservation.owner, ledger) {
    return Err(ForeignOriginal)
  }
  if capacity_reservation_open(bootstrap) {
    if ledger.original_inventory is Some(inventory) {
      if !physical_equal(inventory.bootstrap, bootstrap) {
        return Err(ForeignOriginal)
      }
      // Every original child, including zero bytes, must already have its own
      // retirement. This is not an FD/backing or another Owner's physical ACK.
      match finish_original_ledger_inventory(ledger, true) {
        Ok(true) => ()
        Ok(false) => return Err(Unavailable)
        Err(Resource(issue)) => return Err(Resource(issue))
        Err(_) => return Err(Unavailable)
      }
    } else {
      // Scope construction refused before it installed a census. No ordinary
      // child may have escaped this exact bootstrap-only initialization.
      if ledger.next_capacity_serial != Some(-2) ||
        !original_ledger_has_only_bootstrap(ledger, bootstrap) {
        return Err(Unavailable)
      }
      match settle_capacity(ledger, bootstrap) {
        Err(issue) => return Err(Resource(issue))
        Ok(_) => ()
      }
    }
  }
  value.read_bootstrap = None
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
  if value.cleaned {
    return Err(AlreadyConsumed)
  }
  if value.prepared is Some(original) && physical_equal(original, prepared) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
/// A separate selection, not conversion of an existing Source/Compute child.
/// Only the fixed Node supplier can create the corresponding purpose below.
/// This check does not start a child, reserve bytes or authorize Model use.
pub fn[P] check_node_local_mock_model_run_preparation(
  value : NodeManagedRunAdmission[P],
  prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_preparation(value, prepared) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.purpose is LocalMockModel {
    Ok(())
  } else {
    Err(Unavailable)
  }
}

///|
/// Keep the old purpose's entry closed to a separately admitted Model child.
/// Neither purpose may silently stand in for the other, even at equal limits.
pub fn[P] check_node_source_compute_run_preparation(
  value : NodeManagedRunAdmission[P],
  prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_preparation(value, prepared) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.purpose is SourceCompute {
    Ok(())
  } else {
    Err(Unavailable)
  }
}

///|
// Content is not a conversion of a Source/Compute or Mock Model admission.
// The same ordinary Host must issue this purpose before the keyed acquisition.
pub fn[P] check_node_local_content_run_preparation(
  value : NodeManagedRunAdmission[P],
  prepared : P,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match check_node_managed_run_preparation(value, prepared) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.purpose is LocalContent {
    Ok(())
  } else {
    Err(Unavailable)
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
