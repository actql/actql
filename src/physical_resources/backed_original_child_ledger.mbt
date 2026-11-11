///|
// Same live parent, not a scalar quota or a physical import manufactured by a
// caller. Recheck first-use history at start, not only when the frame is made.
fn[P, C, R] backed_original_child_ready(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
) -> Bool {
  guard backed_live_projection_original(projection, runtime) is Ok(access) &&
    access.ticket is Some(ticket) else {
    return false
  }
  backed_execution_live_state(projection, runtime) == Ok(LiveOpen) &&
  backed_child_usage_unreported(ticket)
}

///|
/// Prepare exactly one original child from the same nominal live admission.
/// Limit DATA and bootstrap amounts cannot supply this original association.
/// Its physical issuer may attach one actual pool-acquisition callback to a
/// growable window; successful return is never funding. Controls, the optional
/// closure and its captures require the original entry envelope before issue.
pub fn[P, C, R] prepare_backed_original_child_ledger(
  projection : BackedExecutionLiveProjection[P, C, R],
  runtime : R,
  acquire_window? : ((Int64, Int64) -> Result[Unit, LedgerIssue])? = None,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  let access = match backed_live_projection_original(projection, runtime) {
    Err(_) => return Err(ForeignOriginal)
    Ok(value) => value
  }
  if projection.child_ledger_issued {
    return Err(AlreadyConsumed)
  }
  if acquire_window is Some(_) &&
    !(access.ticket is Some(ticket) && ticket.current_window is Some(_)) {
    return Err(InvalidOriginal)
  }
  if !backed_original_child_ready(projection, runtime) {
    return Err(Unavailable)
  }
  projection.child_ledger_issued = true
  let value = match
    prepare_imported_child_port(
      1L,
      _ => {
        if backed_original_child_ready(projection, runtime) {
          0
        } else {
          -42
        }
      },
      _ => {
        match backed_execution_live_state(projection, runtime) {
          Ok(LiveOpen) => 0
          Ok(LiveClosing) => 1
          Err(_) => -42
        }
      },
      (_, ordinal) => {
        match backed_execution_live_limits(projection, runtime) {
          Err(_) => -42L
          Ok(limits) =>
            match ordinal {
              0 => limits.planning_work.to_int64()
              1 => limits.attempts.to_int64()
              2 => limits.holdings.to_int64()
              3 => limits.transfer_bytes
              4 => limits.retained_bytes
              5 => limits.execution_bytes
              _ => -42L
            }
        }
      },
      (_, _) => -42L,
      (_, usage) => {
        match report_backed_execution_live_child(projection, runtime, usage) {
          Ok(_) => 0
          Err(_) => -42
        }
      },
      _ => {
        match stop_backed_execution_live_child(access, runtime) {
          Ok(_) => 0
          Err(_) => -42
        }
      },
      fixed_capacities=false,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if access.region is Some(region) {
    value.origin.working = region.working
  }
  if access.ticket is Some(ticket) {
    value.origin.current_window = ticket.current_window
  }
  value.origin.acquire_window = acquire_window
  access.child_origin = Some(value.origin)
  Ok(value)
}

///|
// Called only by the SAME existing physical-owner ACK retirement. Retired
// escaped frames retain their child debt, never the parent/runtime graph via
// these former callbacks. No stop/credit/physical ACK is manufactured here.
fn retire_backed_original_child_origin(
  origin : ImportedChildLedgerOrigin,
) -> Unit {
  origin.stopping = true
  origin.unavailable = true
  origin.admit = retired_backed_original_child_status
  origin.current = retired_backed_original_child_status
  origin.limit = retired_backed_original_child_limit
  origin.capacity = retired_backed_original_child_limit
  origin.report = retired_backed_original_child_report
  origin.stop = retired_backed_original_child_status
  origin.ledger = None
  origin.working = None
  origin.current_window = None
  origin.acquire_window = None
}

///|
fn retired_backed_original_child_status(_ : Int64) -> Int {
  -42
}

///|
fn retired_backed_original_child_limit(_ : Int64, _ : Int) -> Int64 {
  -42L
}

///|
fn retired_backed_original_child_report(_ : Int64, _ : LedgerUsage) -> Int {
  -42
}
