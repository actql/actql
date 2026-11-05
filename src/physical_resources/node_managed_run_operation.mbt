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
pub fn[P, E] reserve_prepared_run_operation(
  value : PreparedRunAdmission[P],
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
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let control = match
    reserve_node_managed_run_operation_control_owned(
      ledger, control, control_retained_bytes, control_execution_bytes,
    ) {
    Err(issue) => return Err(Control(issue))
    Ok(control) => control
  }
  let backing : Result[NodeManagedRunOperationBacking, LedgerIssue] = if physical_attempt {
    reserve_attempt_current(
      ledger,
      transfer_bytes,
      retained_bytes,
      execution_bytes,
      // This installed operation path selects non-Model physical work. Keep
      // the SAME Ledger's configured Model budget neutral, never absent.
      // Actual Model attempts retain their separate amount-bearing entrance.
      quantity_neutral_amounts(ledger),
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

///|
/// The same closed current/original boundary for the actual control-only
/// entrance. No dummy operation body, mode, current proof or scope is created.
pub fn[P, E] reserve_prepared_run_operation_controls(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation?,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[CapacityReservation, NodeManagedRunOperationIssue[E]] {
  if retained_bytes < 0L || execution_bytes < 0L {
    return Err(Control(InvalidCharge))
  }
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  reserve_node_managed_run_operation_control_owned(
    ledger, control, retained_bytes, execution_bytes,
  ).map_err(issue => Control(issue))
}

///|
// Same synchronous Resource frame after its original/post-callback fences.
fn reserve_node_managed_run_operation_control_owned(
  ledger : Ledger,
  control : CapacityReservation?,
  control_retained_bytes : Int64,
  control_execution_bytes : Int64,
) -> Result[CapacityReservation, LedgerIssue] {
  match control {
    Some(control) => {
      if !capacity_reservation_matches(
          ledger, control, control_retained_bytes, control_execution_bytes,
        ) {
        return Err(ForeignOwner)
      }
      Ok(control)
    }
    None => {
      match check_original_reservation_slot_current(ledger) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match
        reserve_capacity_current(
          ledger, control_retained_bytes, control_execution_bytes,
        ) {
        Err(issue) => return Err(issue)
        Ok(control) => Ok(control)
      }
    }
  }
}

///|
/// Grow this SAME original operation when its actual input becomes available,
/// before the next constructor. Physical attempts and transfer/cleanup duties
/// are unchanged. The closed consumer fence follows one current observation;
/// no new token, Root or transferable current proof is issued.
pub fn[P, E] grow_prepared_run_operation_capacity(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  backing : NodeManagedRunOperationBacking,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  if retained_bytes < 0L || execution_bytes < retained_bytes {
    return Err(Control(InvalidCharge))
  }
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let reservation = match backing {
    Construction(capacity) => capacity.reservation
    Physical(reservation) => reservation
  }
  grow_execution_reservation_capacity_current(
    ledger, reservation, retained_bytes, execution_bytes,
  ).map_err(issue => Control(issue))
}

///|
/// The original synchronous constructor has returned its admitted output.
/// Keep its SAME retained backing and spent slot; dispose only workspace.
/// This creates no reservation, attempt, physical stop or cleanup ACK. The
/// closed consumer fence runs after the one original current observation.
pub fn[P, E] complete_prepared_run_operation_construction(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  backing : NodeManagedRunOperationBacking,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard backing is Construction(capacity) else {
    return Err(Control(InvalidCharge))
  }
  let retained = capacity.reservation.retention
  resize_capacity_reservation_current(
    ledger,
    capacity,
    retained,
    Int64::min(retained, capacity.reservation.execution),
  ).map_err(issue => Control(issue))
}

///|
/// Successful detached constructor DATA keeps its measured retained envelope
/// on the SAME pure backing. The original consumer observes real child close
/// before this entrance; numbers never certify physical cleanup or permission.
/// Refusal preserves the complete old backing and cumulative history.
pub fn[P, E] complete_prepared_run_operation_construction_output(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  backing : NodeManagedRunOperationBacking,
  retained_bytes : Int64,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard backing is Construction(capacity) &&
    retained_bytes >= 0L &&
    retained_bytes <= capacity.reservation.retention else {
    return Err(Control(InvalidCharge))
  }
  resize_capacity_reservation_current(
    ledger,
    capacity,
    retained_bytes,
    Int64::min(retained_bytes, capacity.reservation.execution),
  ).map_err(issue => Control(issue))
}

///|
/// Grow only the SAME retained pure-constructor reservation immediately before
/// its callback. The original consumer/current frame is the same as completion;
/// neither this byte resize nor completion creates an attempt or a new owner.
pub fn[P, E] begin_prepared_run_operation_construction(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  backing : NodeManagedRunOperationBacking,
  execution_bytes : Int64,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  if execution_bytes < 0L {
    return Err(Control(InvalidCharge))
  }
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard backing is Construction(capacity) else {
    return Err(Control(InvalidCharge))
  }
  resize_capacity_reservation_current(
    ledger,
    capacity,
    capacity.reservation.retention,
    execution_bytes,
  ).map_err(issue => Control(issue))
}

///|
/// Resize the SAME existing management-control reservation at its actual
/// synchronous constructor boundary. The original consumer/current frame
/// precedes the callback-free resize; no attempt, resource or Root is created.
pub fn[P, E] resize_prepared_run_operation_control_construction(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  if retained_bytes < 0L || execution_bytes < 0L {
    return Err(Control(InvalidCharge))
  }
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  resize_capacity_reservation_current(
    ledger, control, retained_bytes, execution_bytes,
  ).map_err(issue => Control(issue))
}

///|
// Original Node entry forwards the same original to the shared closed operation.
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
  reserve_prepared_run_operation(
    NodePreparedRun(value),
    prepared,
    ledger,
    original,
    control,
    control_retained_bytes,
    control_execution_bytes,
    physical_attempt,
    transfer_bytes,
    retained_bytes,
    execution_bytes,
  )
}

///|
// Original Node entry forwards the same original to the shared closed operation.
pub fn[P, E] reserve_node_managed_run_operation_controls(
  value : NodeManagedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation?,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[CapacityReservation, NodeManagedRunOperationIssue[E]] {
  reserve_prepared_run_operation_controls(
    NodePreparedRun(value),
    prepared,
    ledger,
    original,
    control,
    retained_bytes,
    execution_bytes,
  )
}

///|
// Original Node entry forwards the same original to the shared closed operation.
pub fn[P, E] complete_node_managed_run_operation_construction(
  value : NodeManagedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  backing : NodeManagedRunOperationBacking,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  complete_prepared_run_operation_construction(
    NodePreparedRun(value),
    prepared,
    ledger,
    original,
    backing,
  )
}

///|
// Original Node entry forwards the same original to the shared closed operation.
pub fn[P, E] begin_node_managed_run_operation_construction(
  value : NodeManagedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  backing : NodeManagedRunOperationBacking,
  execution_bytes : Int64,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  begin_prepared_run_operation_construction(
    NodePreparedRun(value),
    prepared,
    ledger,
    original,
    backing,
    execution_bytes,
  )
}

///|
// Original Node entry forwards the same original to the shared closed operation.
pub fn[P, E] resize_node_managed_run_operation_control_construction(
  value : NodeManagedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, NodeManagedRunOperationIssue[E]] {
  resize_prepared_run_operation_control_construction(
    NodePreparedRun(value),
    prepared,
    ledger,
    original,
    control,
    retained_bytes,
    execution_bytes,
  )
}
