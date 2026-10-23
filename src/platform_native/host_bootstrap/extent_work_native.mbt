///|
/// Cumulative physical backing-extent work, never capacity or a cleanup ACK.
/// Nested allocator work, control writes and anonymous initial zero supply
/// are outside these observations.
pub(all) struct NativeExtentWork {
  allocations : Int64
  allocated_bytes : Int64
  zeroed_bytes : Int64
  retirements : Int64
  retired_bytes : Int64
} derive(Eq, Debug)

///|
#borrow(backing, output)
extern "C" fn extent_work_ffi(
  backing : Backing,
  output : FixedArray[Int64],
  count : Int,
) -> Int = "actql_bootstrap_extent_work"

///|
/// The original backing loan must already be entered. This observation never
/// enters another scope and retains no pointer into the physical holding.
pub fn[T] NativeHostBootstrap::observe_extent_work(
  self : NativeHostBootstrap[T],
  original : T,
  borrow : NativeBootstrapBorrow[T],
) -> Result[NativeExtentWork, NativeBootstrapIssue] {
  match self.require_borrow_current(original, borrow) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if borrow.scopes <= 0L {
    return Err(Unavailable)
  }
  let values = FixedArray::make(5, 0L)
  let code = extent_work_ffi(self.backing, values, 5)
  if code != 0 {
    return Err(Physical(code))
  }
  Ok({
    allocations: values[0],
    allocated_bytes: values[1],
    zeroed_bytes: values[2],
    retirements: values[3],
    retired_bytes: values[4],
  })
}
