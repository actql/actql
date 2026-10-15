///|
/// Observe the existing physical charge of one allocation in this original
/// installed Host. This uses the same provider rounding as allocate; it does
/// not allocate, reserve, inspect available space or retain a descriptor cache.
/// Price each simultaneously live allocation separately, including old/new
/// buffers. This is not an aggregate representation bound, child-domain control
/// quote, baseline, permission or cleanup acknowledgment. Caller control and
/// the returned observation still require their own existing lifetime funding.
pub fn[T] NativeHostBootstrap::allocation_charge(
  self : NativeHostBootstrap[T],
  original : T,
  bytes : Int64,
) -> Result[Int64, NativeBootstrapIssue] {
  match self.require_current(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let rounded = rounded_bytes_ffi(self.backing, bytes)
  if rounded <= 0L {
    return Err(Unavailable)
  }
  Ok(rounded)
}
