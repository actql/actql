///|
priv enum ControlTerminalClose {
  ControlClientPending
  ControlSlotPending
  ControlSlotUnknown
  ControlHandlesRetired
}

///|
/// The existing Slot close consumes its descriptor even on failure. Record
/// that one observation here; a closed descriptor is not a later close ACK.
/// This is caller cleanup progress, never Run or remote release authority.
fn retry_control_terminal_handles(
  original : (@http.Client, @slot.NativeExecutorSlot),
  progress : Ref[ControlTerminalClose],
) -> Bool {
  if progress.val is ControlClientPending {
    guard original.0.close_checked() is Ok(_) else { return false }
    progress.val = ControlSlotPending
  }
  if progress.val is ControlSlotPending {
    return retry_control_slot_close(original.1, progress)
  }
  progress.val is ControlHandlesRetired
}

///|
fn retry_control_slot_close(
  original : @slot.NativeExecutorSlot,
  progress : Ref[ControlTerminalClose],
) -> Bool {
  if progress.val is ControlSlotPending {
    if !original.close() {
      progress.val = ControlSlotUnknown
      return false
    }
    progress.val = ControlHandlesRetired
  }
  progress.val is ControlHandlesRetired
}

///|
/// Reclaim's closed Store/Journal cannot stand in for its Slot close. Keep
/// the same caller stack and original descriptor on missing observation.
fn retain_control_reclaim_slot_close(
  original : @slot.NativeExecutorSlot,
) -> Unit {
  let progress = Ref(ControlSlotPending)
  install_partial_holder_cleanup_signal()
  ignore(
    retain_holder_cleanup_lifetime(
      original,
      same => retry_control_slot_close(same, progress),
      () => CleanupInputEnded,
      wait_holder_cleanup_lifetime_signal,
      (_, _) => report("orphan-slot-cleanup-pending", []),
    ),
  )
}

///|
/// Keep both original handles in the existing lifetime shell. Unknown Slot
/// close never retries its consumed number or opens a replacement descriptor.
fn retain_control_terminal_handles(
  client : @http.Client,
  slot : @slot.NativeExecutorSlot,
) -> Unit {
  let progress = Ref(ControlClientPending)
  install_partial_holder_cleanup_signal()
  ignore(
    retain_holder_cleanup_lifetime(
      (client, slot),
      same => retry_control_terminal_handles(same, progress),
      () => CleanupInputEnded,
      wait_holder_cleanup_lifetime_signal,
      (_, _) => report("control-terminal-cleanup-pending", []),
    ),
  )
}
