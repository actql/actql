///|
priv struct NativeTaskResources {
  attempt : @planning.DuckDBComputeAttempt
  reservation : Reservation
  retention : Int64
  scratch : Int64
  mut native_settled : Bool
  mut disposed : Bool
  mut failed_holding : Holding?
  resident : ResidentInputs?
  resident_output : ResidentPendingOutput?
}

///|
fn native_task_resource(
  run : CapturedDAG,
  attempt : @planning.DuckDBComputeAttempt,
) -> (Int, NativeTaskResources)? {
  for task, value in run.native_resources {
    if value is Some(value) && physical_equal(value.attempt, attempt) {
      return Some((task, value))
    }
  }
  None
}

///|
/// Trusted transport charges the exact run-owned reservation before send/accept.
pub fn charge_captured_duckdb_transfer(
  run : CapturedDAG,
  attempt : @planning.DuckDBComputeAttempt,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  guard native_task_resource(run, attempt) is Some((_, resource)) else {
    return Err(ForeignOwner)
  }
  if resource.disposed || resource.native_settled {
    return Err(ClosedReservation)
  }
  charge_transfer(run.ledger, resource.reservation, bytes)
}

///|
/// Native stop/cleanup acknowledgement, not cancellation. Completion scratch
/// and provisional retention remain reserved until completion or disposal.
pub fn settle_captured_duckdb_native(
  run : CapturedDAG,
  attempt : @planning.DuckDBComputeAttempt,
  confirmed : Bool,
) -> Result[Unit, LedgerIssue] {
  guard native_task_resource(run, attempt) is Some((task, resource)) else {
    return Err(ForeignOwner)
  }
  if resource.native_settled {
    return Ok(())
  }
  if !confirmed {
    return mark_cleanup_pending(run.ledger, resource.reservation)
  }
  let result = if resource.disposed {
    settle_reservation(run.ledger, resource.reservation)
  } else {
    settle_execution_reservation(
      run.ledger,
      resource.reservation,
      remaining_execution=resource.scratch,
    )
  }
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      resource.native_settled = true
      if resource.resident is Some(read) {
        // The task connection/transaction really stopped. Shared DB capacity
        // remains reserved independently through its environment lifetime.
        return_resident_inputs(read) |> ignore
      }
      if resource.disposed {
        captured_cleanup_confirmed(run, attempt)
        run.native_resources[task] = None
      }
      Ok(())
    }
  }
}

///|
/// Dispose owned MoonBit buffers/port. Unconfirmed native reservations remain.
pub fn close_captured_duckdb_task(
  run : CapturedDAG,
  attempt : @planning.DuckDBComputeAttempt,
) -> Unit {
  guard native_task_resource(run, attempt) is Some((task, resource)) else {
    return
  }
  if resource.disposed {
    return
  }
  if run.running is Some((_, active)) && physical_equal(active, attempt) {
    stop_captured_dag(run)
  }
  resource.disposed = true
  @planning.close_duckdb_compute_attempt(attempt)
  close_captured_task_output(run, task)
  if resource.native_settled {
    if resource.failed_holding is Some(holding) {
      release_allocation(run.ledger, holding) |> ignore
    }
    if resource.reservation.open {
      settle_reservation(run.ledger, resource.reservation) |> ignore
    }
    captured_cleanup_confirmed(run, attempt)
    // Do not retain a closed attempt's input graph after releasing its ledger
    // responsibility. The caller may still own its diagnostic handle.
    run.native_resources[task] = None
  }
}
