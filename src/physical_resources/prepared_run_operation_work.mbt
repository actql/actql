///|
// Pure Resource links after this SAME operation's synchronous current fence.
// No physical/current callback, byte resize or owner-retired callback belongs
// inside a work segment. A changed holder or stopped child closes the view.
fn[P] prepared_run_operation_work_binding(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  control : CapacityReservation,
) -> Bool {
  if !physical_equal(control.reservation.owner, ledger) ||
    !control.reservation.open {
    return false
  }
  let child = match value {
    NodePreparedRun(owner) => {
      if check_node_managed_run_preparation(owner, prepared) is Err(_) {
        return false
      }
      prepared_run_operation_work_node_child(owner)
    }
    BackedPreparedRun(owner) => {
      if !(owner.original is Some(original) && physical_equal(original, owner)) ||
        owner.cleaned ||
        owner.transitioning {
        return false
      }
      guard owner.holder is Some(holder) &&
        preparation_body_borrow_value(holder) is Some(body) &&
        physical_equal(body, prepared) &&
        !preparation_body_retirement_started(holder) else {
        return false
      }
      Some(owner.child)
    }
  }
  guard child is Some(child) &&
    child.original is Some(original) &&
    physical_equal(original, child) &&
    child.taken &&
    !child.stop_attempted &&
    child.pending_report is None &&
    child.pending_report_issue is None &&
    child.ledger is Some(original_ledger) &&
    physical_equal(original_ledger, ledger) &&
    !child.origin.stopping &&
    !child.origin.unavailable &&
    !child.origin.acquiring_window &&
    ledger.imported_child is Some(origin) &&
    physical_equal(origin, child.origin) &&
    origin.ledger is Some(original_ledger) &&
    physical_equal(original_ledger, ledger) else {
    return false
  }
  check_original_resources_mutable_current(ledger) is Ok(_)
}

///|
/// One synchronous work view on an existing admitted operation control.
/// It consumes the SAME planning counter, never a quota, Root, owner, Ledger
/// or transferable current proof. The closed caller retains its own flight
/// latch and supplies a callback-free original-lifetime check. All allocating
/// Resource callbacks, reentry and awaits must occur outside this segment.
fn[P, R, E] with_prepared_run_operation_control_work_selected(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation,
  live : () -> Bool,
  publication_work : PreparationPhaseWorkContinuation64?,
  work : ((Int) -> Result[Unit, LedgerIssue]) -> Result[
    R,
    NodeManagedRunOperationIssue[E],
  ],
) -> Result[R, NodeManagedRunOperationIssue[E]] {
  match
    check_prepared_run_operation_original(value, prepared, ledger, original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !prepared_run_operation_work_binding(value, prepared, ledger, control) ||
    !live() {
    return Err(Control(ForeignOwner))
  }
  // These are existing identity/history fences, not another usage ledger.
  // A constructor/resource callback changes this cut and requires a fresh
  // segment. Only this segment's planning consumption may change its usage.
  let capacity_serial = ledger.next_capacity_serial
  let attempt_serial = ledger.next_attempt_serial
  let holding_serial = ledger.next_holding_serial
  let control_retained = control.reservation.retention
  let control_execution = control.reservation.execution
  // Borrow the immutable usage snapshot. Update this fence only after this
  // view's own debit; an unrelated resize/settlement cannot keep it current.
  let expected_usage = Ref(ledger.usage)
  let active = Ref(true)
  let spending = Ref(false)
  defer {
    active.val = false
  }
  let spend = fn(units : Int) -> Result[Unit, LedgerIssue] {
    if !active.val || spending.val {
      active.val = false
      return Err(ForeignOwner)
    }
    spending.val = true
    defer {
      spending.val = false
    }
    if ledger.usage != expected_usage.val ||
      ledger.next_capacity_serial != capacity_serial ||
      ledger.next_attempt_serial != attempt_serial ||
      ledger.next_holding_serial != holding_serial ||
      control.reservation.retention != control_retained ||
      control.reservation.execution != control_execution ||
      !prepared_run_operation_work_binding(value, prepared, ledger, control) {
      active.val = false
      return Err(ForeignOwner)
    }
    let current = live()
    if !active.val ||
      !current ||
      ledger.usage != expected_usage.val ||
      !prepared_run_operation_work_binding(value, prepared, ledger, control) {
      active.val = false
      return Err(ForeignOwner)
    }
    if units == 0 {
      return Ok(())
    }
    let charged = match publication_work {
      None => charge_planning_current(ledger, units)
      Some(receipt) =>
        if !physical_equal(receipt.ledger_original, ledger) {
          Err(ForeignOwner)
        } else {
          spend_preparation_phase_work_continuation64(receipt, units.to_int64()).map_err(_ => {
              LedgerIssue::PlanningLimit
            },
          )
        }
    }
    match charged {
      Err(issue) => {
        active.val = false
        Err(issue)
      }
      Ok(_) => {
        expected_usage.val = ledger.usage
        Ok(())
      }
    }
  }
  match work(spend) {
    Err(issue) => Err(issue)
    Ok(result) =>
      match spend(0) {
        Err(issue) => Err(Control(issue))
        Ok(_) => Ok(result)
      }
  }
}

///|
// Unchanged dispatch-planning entrance.
pub fn[P, R, E] with_prepared_run_operation_control_work(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation,
  live : () -> Bool,
  work : ((Int) -> Result[Unit, LedgerIssue]) -> Result[
    R,
    NodeManagedRunOperationIssue[E],
  ],
) -> Result[R, NodeManagedRunOperationIssue[E]] {
  with_prepared_run_operation_control_work_selected(
    value,
    prepared,
    ledger,
    original,
    control,
    live,
    None,
    work,
  )
}

///|
// Closed construction alternative uses one already-issued SAME Run receipt.
// It changes no planning/attempt/external-operation counter or allowance.
pub fn[P, R, E] with_prepared_run_operation_control_publication_work(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  original : () -> Result[Unit, E],
  control : CapacityReservation,
  live : () -> Bool,
  receipt : PreparationPhaseWorkContinuation64,
  work : ((Int) -> Result[Unit, LedgerIssue]) -> Result[
    R,
    NodeManagedRunOperationIssue[E],
  ],
) -> Result[R, NodeManagedRunOperationIssue[E]] {
  if !physical_equal(receipt.ledger_original, ledger) {
    return Err(Control(ForeignOwner))
  }
  with_prepared_run_operation_control_work_selected(
    value,
    prepared,
    ledger,
    original,
    control,
    live,
    Some(receipt),
    work,
  )
}

///|
// The same body borrower retains the original input/body/reservation across
// adoption. Numeric meter storage must already be funded by its caller.
pub fn[P] begin_prepared_run_publication_work(
  value : PreparedRunAdmission[P],
  prepared : P,
  ledger : Ledger,
  maximum : Int64,
) -> Result[PreparationPhaseWorkContinuation64, ImportedChildLedgerIssue] {
  match check_prepared_run_admission(value, prepared, ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let holder = match value {
    NodePreparedRun(owner) => {
      match check_node_managed_run_preparation(owner, prepared) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard prepared_run_operation_work_node_body(owner) is Some(holder) else {
        return Err(Unavailable)
      }
      holder
    }
    BackedPreparedRun(owner) => {
      match check_backed_prepared_run_binding(owner, prepared, ledger) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      guard owner.holder is Some(holder) else { return Err(Unavailable) }
      holder
    }
  }
  let result : Ref[PreparationPhaseWorkContinuation64?] = Ref(None)
  match
    (holder.reserve_phase_original)(
      prepared,
      0L,
      0L,
      PublicationProofWork(maximum, result),
    ) {
    Err(_) => Err(Unavailable)
    Ok(_) =>
      match result.val {
        Some(receipt) => Ok(receipt)
        None => Err(Unavailable)
      }
  }
}
