///|
// A borrowed view owns only its reader token, not the allocation or arena.
enum WorkspaceBacking {
  OwnedCapacity
  BorrowedAllocation(@resources.SharedBorrow)
  ReturnedBorrow
}

///|
/// Physical workspace custody on the supplied existing root Ledger. This loan
/// does not admit a Run, authorize I/O or decide cancellation/completion.
pub struct WorkspaceLoan {
  capacity : @resources.SharedCapacity
  priv mut backing : WorkspaceBacking
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
        backing: OwnedCapacity,
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
/// Borrow one existing live allocation without reserving execution again.
/// The physical installer still owns extent, generation, placement and the
/// separately funded control/read envelope; this view supplies none of them.
pub fn borrow_workspace(
  capacity : @resources.SharedCapacity,
  allocation : @resources.SharedAllocation,
  physical_stop : () -> Bool,
  physical_cleanup : () -> Bool,
) -> Result[WorkspaceLoan, BufferIssue] {
  @resources.borrow_shared_capacity(capacity, allocation)
  .map_err(Resource)
  .map(borrow => {
    capacity,
    backing: BorrowedAllocation(borrow),
    physical_stop,
    physical_cleanup,
    closing: false,
    stopped: false,
    cleaned: false,
    settled: false,
  })
}

///|
/// Request retirement without releasing the reservation before physical facts.
/// Retry uses the same loan and remembers already observed stop/cleanup facts.
pub fn close_workspace(loan : WorkspaceLoan) -> Result[Unit, BufferIssue] {
  if loan.settled {
    return Ok(())
  }
  if !loan.closing {
    match loan.backing {
      OwnedCapacity =>
        match @resources.close_shared_capacity(loan.capacity) {
          Err(issue) => return Err(Resource(issue))
          Ok(_) => ()
        }
      BorrowedAllocation(_) => ()
      ReturnedBorrow => return Err(CleanupPending)
    }
    loan.closing = true
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
  let result = match loan.backing {
    OwnedCapacity => @resources.settle_shared_capacity(loan.capacity)
    BorrowedAllocation(borrow) => @resources.return_shared_capacity(borrow)
    ReturnedBorrow => return Err(CleanupPending)
  }
  match result {
    Err(issue) => Err(Resource(issue))
    Ok(_) => {
      if loan.backing is BorrowedAllocation(_) {
        // Drop the returned token's allocation backreference. The installing
        // arena retains its own capacity; this is not its retirement ACK.
        loan.backing = ReturnedBorrow
      }
      loan.settled = true
      Ok(())
    }
  }
}
