///|
/// Cleanup-only preparation for the same original physical region Owner.
/// Known transport endpoints retire, but the original anchor remains held.
/// This is not permission to launch, a Stop or a region/WorkspaceLoan ACK.
pub fn NativeScopedExecutorHolder::prepare_unstarted_cleanup(
  self : NativeScopedExecutorHolder,
) -> Result[Unit, NativeExecutorSlotIssue] {
  if scoped_anchor_thread_ffi(self.anchor) != 0 {
    return Err(LockFailed)
  }
  if self.child is Some(_) {
    return Err(Busy)
  }
  if self.closed {
    return Err(Closed)
  }
  // Never infer no-child from a caller's spawn error or a missing PID. After
  // an attempt this seam needs the original duplex call's observed return.
  // The old one-way attempted path remains outside this new cleanup seam.
  if self.attempted && (self.duplex is None || !self.duplex_spawn_returned) {
    return Err(Busy)
  }
  self.retire_unstarted_transport()
}
