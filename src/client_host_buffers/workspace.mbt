///|
/// Physical workspace custody on the supplied existing root Ledger. This loan
/// does not admit a Run, authorize I/O or decide cancellation/completion.
pub struct WorkspaceLoan {
  capacity : @resources.SharedCapacity
  physical_stop : () -> Bool
  physical_cleanup : () -> Bool
  mut closing : Bool
  mut stopped : Bool
  mut cleaned : Bool
  mut settled : Bool
}

///|
/// Reserve the full configured workspace before its physical allocation.
pub fn reserve_workspace(
  ledger : @resources.Ledger,
  bytes : Int64,
  physical_stop : () -> Bool,
  physical_cleanup : () -> Bool,
) -> Result[WorkspaceLoan, BufferIssue] {
  match @resources.reserve_shared_capacity(ledger, bytes) {
    Err(issue) => Err(Resource(issue))
    Ok(capacity) =>
      Ok({
        capacity,
        physical_stop,
        physical_cleanup,
        closing: false,
        stopped: false,
        cleaned: false,
        settled: false,
      })
  }
}

///|
/// Request retirement without releasing the reservation before physical facts.
/// Retry uses the same loan and remembers already observed stop/cleanup facts.
pub fn close_workspace(loan : WorkspaceLoan) -> Result[Unit, BufferIssue] {
  if loan.settled {
    return Ok(())
  }
  if !loan.closing {
    match @resources.close_shared_capacity(loan.capacity) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => loan.closing = true
    }
  }
  if !loan.stopped {
    if !(loan.physical_stop)() {
      return Err(CleanupPending)
    }
    loan.stopped = true
  }
  if !loan.cleaned {
    if !(loan.physical_cleanup)() {
      return Err(CleanupPending)
    }
    loan.cleaned = true
  }
  match @resources.settle_shared_capacity(loan.capacity) {
    Err(issue) => Err(Resource(issue))
    Ok(_) => {
      loan.settled = true
      Ok(())
    }
  }
}
