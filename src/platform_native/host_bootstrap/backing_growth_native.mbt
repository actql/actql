///|
#borrow(backing)
extern "C" fn backing_capacity_bytes_ffi(backing : Backing) -> Int64 = "actql_bootstrap_capacity_bytes"

///|
#borrow(backing)
extern "C" fn growth_control_bytes_ffi(
  backing : Backing,
  additional : Int64,
) -> Int64 = "actql_bootstrap_growth_control_bytes"

///|
#borrow(backing)
extern "C" fn grow_backing_ffi(
  backing : Backing,
  expected : Int64,
  additional : Int64,
) -> Int64 = "actql_bootstrap_grow"

///|
/// Explicit non-moving acquisition by the SAME anonymous root and reservation.
/// Reserve complete segment and controls before mmap; refuse before the caller
/// constructs payload. Old loans, generations and allocations remain unchanged.
/// This is not carved-domain growth, implicit fallback or a memory-size grant.
pub fn[T] NativeHostBootstrap::grow_backing(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
  bytes : Int64,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if scope.scopes <= 0L {
    return Err(Unavailable)
  }
  guard self.control is Some(control) else { return Err(Unavailable) }
  let before = @resources.shared_capacity_usage(self.capacity).capacity
  let physical = backing_capacity_bytes_ffi(self.backing)
  if physical != before || bytes < before {
    return Err(Unavailable)
  }
  if bytes == before {
    return Ok(())
  }
  let additional = bytes - before
  let controls = growth_control_bytes_ffi(self.backing, additional)
  let control_before = @resources.shared_allocation_usage(control).bytes
  if controls <= 0L || controls >= additional || control_before > before {
    return Err(Unavailable)
  }
  let growth = match
    @resources.begin_shared_capacity_growth(
      self.capacity,
      control,
      bytes,
      controls,
    ) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  self.growth = Some(growth)
  let result = grow_backing_ffi(self.backing, before, additional)
  if result < 0L {
    // The physical port guarantees an atomic failed acquisition. Only this
    // transaction's recorded unused suffix can be returned to the same owner.
    match @resources.abort_shared_capacity_growth_after_cleanup(growth) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => self.growth = None
    }
    return Err(Physical(result.to_int()))
  }
  if result != controls {
    // Do not release a charge after a surprising successful physical outcome.
    // The same original keeps every mapping until actual cleanup acknowledges.
    return Err(Unavailable)
  }
  match @resources.complete_shared_capacity_growth_after_acquisition(growth) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => self.growth = None
  }
  Ok(())
}

///|
/// Same selected finite Root facility; already acquired bytes need no repeat
/// acquisition. This neither enlarges declared policy nor creates a child.
pub fn[T] NativeHostBootstrap::ensure_backing_capacity(
  self : NativeHostBootstrap[T],
  original : T,
  scope : NativeBootstrapBorrow[T],
  bytes : Int64,
) -> Result[Unit, NativeBootstrapIssue] {
  match self.require_borrow_current(original, scope) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if bytes <= 0L {
    return Err(Unavailable)
  }
  let current = @resources.shared_capacity_usage(self.capacity).capacity
  if bytes <= current {
    return Ok(())
  }
  self.grow_backing(original, scope, bytes)
}
