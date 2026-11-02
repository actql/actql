///|
/// The finite controller may enter terminal cleanup immediately after reclaim.
/// Retain that helper's actual close observation, not descriptor absence.
test "controller slot handoff keeps the same reclaim close through terminal cleanup" {
  let (library, client, slot, path) = control_terminal_fixture(
    "handoff-confirmed",
  )
  let slot_progress = Ref(ControlSlotPending)
  retain_control_reclaim_slot_close(slot, slot_progress)
  assert_true(
    slot_progress.val is ControlHandlesRetired(same) &&
    physical_equal(same, slot),
  )
  // A distinct terminal phase still has to close its actual Client.
  let terminal = Ref(ControlClientPending)
  assert_true(
    retry_control_terminal_handles((client, slot), terminal, slot_progress),
  )
  assert_true(client.response_limit() is Err(Closed))
  let independent = @slot.open_native_executor_slot(path).unwrap()
  assert_true(independent.try_acquire().unwrap())
  assert_true(
    retry_control_terminal_handles((client, slot), terminal, slot_progress),
  )
  assert_eq(independent.verify_current_hold(), Ok(()))
  assert_true(independent.close())
  library.close_checked().unwrap()
}

///|
test "controller slot handoff refuses a confirmed observation for a different Slot" {
  let (library, client, slot, path) = control_terminal_fixture(
    "handoff-foreign",
  )
  let slot_progress = Ref(ControlSlotPending)
  retain_control_reclaim_slot_close(slot, slot_progress)
  let independent = @slot.open_native_executor_slot(path).unwrap()
  assert_true(independent.try_acquire().unwrap())
  let terminal = Ref(ControlClientPending)
  assert_false(
    retry_control_terminal_handles(
      (client, independent),
      terminal,
      slot_progress,
    ),
  )
  assert_true(client.response_limit() is Err(Closed))
  assert_eq(independent.verify_current_hold(), Ok(()))
  assert_true(independent.close())
  library.close_checked().unwrap()
}

///|
test "controller slot handoff keeps an unobserved close Unknown in terminal cleanup" {
  let (library, client, slot, path) = control_terminal_fixture(
    "handoff-unknown",
  )
  // This descriptor was consumed outside this caller's observation. It is
  // not an injected kernel failure; no later observer may infer its ACK.
  assert_true(slot.close())
  let slot_progress = Ref(ControlSlotPending)
  assert_false(retry_control_slot_close(slot, slot_progress))
  assert_true(slot_progress.val is ControlSlotUnknown)
  let independent = @slot.open_native_executor_slot(path).unwrap()
  assert_true(independent.try_acquire().unwrap())
  let terminal = Ref(ControlClientPending)
  assert_false(
    retry_control_terminal_handles((client, slot), terminal, slot_progress),
  )
  assert_true(terminal.val is ControlSlotUnknown)
  assert_false(
    retry_control_terminal_handles((client, slot), terminal, slot_progress),
  )
  assert_eq(independent.verify_current_hold(), Ok(()))
  assert_true(independent.close())
  library.close_checked().unwrap()
  assert_true(slot_progress.val is ControlSlotUnknown)
}
