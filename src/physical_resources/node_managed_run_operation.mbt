///|
/// The existing two operation backings. Neither variant is another Owner,
/// physical Start, permission or cleanup acknowledgment.
pub(all) enum NodeManagedRunOperationBacking {
  Construction(CapacityReservation)
  Physical(Reservation)
}

///|
/// Preserve the original consumer refusal separately from admission and
/// control-capacity failures. A body refusal returns its actual control below.
pub(all) enum NodeManagedRunOperationIssue[E] {
  Admission(ImportedChildLedgerIssue)
  Original(E)
  Control(LedgerIssue)
}

///|
/// One closed installed-Run reservation boundary. The same original current
/// runs once; the non-escaping Core consumer checks its own original links
/// BEFORE any reservation/history mutation. No callback/proof is retained or
/// exported to a provider. The private allocators follow the callback-free
/// post-fences in this call; no reusable current capability leaves it.
/// A body quota refusal returns the actual control, which the SAME caller must
/// retain before returning that refusal. No serial, charge or peak is refunded.
pub fn[P, E] reserve_node_managed_run_operation(
  value : NodeManagedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation?,
  control_retained_bytes : Int64,
  control_execution_bytes : Int64,
  physical_attempt : Bool,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  (CapacityReservation, Result[NodeManagedRunOperationBacking, LedgerIssue]),
  NodeManagedRunOperationIssue[E],
] {
  if control_retained_bytes < 0L ||
    control_execution_bytes < 0L ||
    transfer_bytes < 0L ||
    retained_bytes < 0L ||
    execution_bytes < 0L {
    return Err(Control(InvalidCharge))
  }
  match check_node_managed_run_mutable_admission(value, prepared, ledger) {
    Err(issue) => return Err(Admission(issue))
    Ok(_) => ()
  }
  match original() {
    Err(issue) => return Err(Original(issue))
    Ok(_) => ()
  }
  // The internal continuation carries no authority. Recheck Resource's own
  // tuple and mutable state without invoking physical current a second time.
  match check_node_managed_run_preparation(value, prepared) {
    Err(issue) => return Err(Admission(issue))
    Ok(_) => ()
  }
  guard value.ledger is Some(bound) && physical_equal(bound, ledger) else {
    return Err(Admission(ForeignOriginal))
  }
  match check_imported_original_child_ledger_current(value.child, ledger) {
    Err(issue) => return Err(Admission(issue))
    Ok(_) => ()
  }
  match check_original_resources_mutable_current(ledger) {
    Err(issue) => return Err(Admission(Resource(issue)))
    Ok(_) => ()
  }
  let control = match control {
    Some(control) => {
      if !capacity_reservation_matches(
          ledger, control, control_retained_bytes, control_execution_bytes,
        ) {
        return Err(Control(ForeignOwner))
      }
      control
    }
    None => {
      match check_original_reservation_slot_current(ledger) {
        Err(issue) => return Err(Control(issue))
        Ok(_) => ()
      }
      match
        reserve_capacity_current(
          ledger, control_retained_bytes, control_execution_bytes,
        ) {
        Err(issue) => return Err(Control(issue))
        Ok(control) => control
      }
    }
  }
  let backing : Result[NodeManagedRunOperationBacking, LedgerIssue] = if physical_attempt {
    reserve_attempt_current(
      ledger,
      transfer_bytes,
      retained_bytes,
      execution_bytes,
      None,
    ).map(original => Physical(original))
  } else {
    match check_original_reservation_slot_current(ledger) {
      Err(issue) => Err(issue)
      Ok(_) =>
        reserve_capacity_current(ledger, retained_bytes, execution_bytes).map(original => {
          Construction(original)
        })
    }
  }
  Ok((control, backing))
}
