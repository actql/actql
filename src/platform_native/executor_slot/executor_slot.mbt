///|
pub(all) enum NativeExecutorSlotIssue {
  UnsupportedTarget
  InvalidConfiguration
  /// The slot file could not be opened as a private regular file of this
  /// user.
  OpenFailed
  /// Another process (and its descendants) holds the executor slot.
  Busy
  /// The descriptor no longer names the slot file: it was replaced.
  Replaced
  /// This process does not hold the slot through the inherited descriptor.
  NotHeld
  SpawnFailed
  WaitFailed
  Closed
  LockFailed
} derive(Eq, Debug)

///|
/// How a started holder process ended.
pub(all) enum NativeExecutorSlotExit {
  Exited(Int)
  Signaled(Int)
} derive(Eq, Debug)

///|
/// The descriptor number a holder process receives the slot lock on.
pub const NATIVE_EXECUTOR_SLOT_INHERITED_FD : Int = 3
