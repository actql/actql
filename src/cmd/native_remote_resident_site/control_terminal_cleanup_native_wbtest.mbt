///|
fn control_terminal_fixture(
  name : String,
) -> (@http.Library, @http.Client, @slot.NativeExecutorSlot, String) raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(path) else {
    fail("selected controller cleanup requires the retained HTTP component")
    abort("missing HTTP component")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_EXECUTOR_SLOT_ROOT") is Some(root) else {
    fail("selected controller cleanup requires an owned Slot root")
    abort("missing Slot root")
  }
  let library = @http.load_library_with_custody(path).unwrap()
  let client = library
    .create_authenticated_client_with_custody(
      "/fixture/ca.pem",
      Bearer("/fixture/token"),
      64L,
      10,
      20,
    )
    .unwrap()
  let slot_path = root + "/" + name + ".lock"
  let slot = @slot.open_native_executor_slot(slot_path).unwrap()
  assert_true(slot.try_acquire().unwrap())
  (library, client, slot, slot_path)
}

///|
/// Actual Client metadata and Slot descriptor cleanup only. No request, Host
/// bootstrap, child process, remote Run or canonical Resident is executed.
test "controller terminal retains the confirmed original Client and Slot close observations" {
  let (library, client, slot, path) = control_terminal_fixture(
    "terminal-confirmed",
  )
  let progress = Ref(ControlClientPending)
  assert_true(retry_control_terminal_handles((client, slot), progress))
  assert_true(progress.val is ControlHandlesRetired)
  assert_true(client.response_limit() is Err(Closed))
  let independent = @slot.open_native_executor_slot(path).unwrap()
  assert_true(independent.try_acquire().unwrap())
  // Recorded completion must not reclose the consumed original descriptor.
  assert_true(retry_control_terminal_handles((client, slot), progress))
  assert_eq(independent.verify_current_hold(), Ok(()))
  assert_true(independent.close())
  library.close_checked().unwrap()
}

///|
test "controller terminal keeps an unobserved consumed Slot pending without closing a replacement" {
  let (library, client, slot, path) = control_terminal_fixture(
    "terminal-unknown",
  )
  // Consume the actual descriptor outside the terminal observer. Its later
  // false close result cannot establish the missing original observation;
  // this is not an injected operating-system close error or physical stop.
  assert_true(slot.close())
  let independent = @slot.open_native_executor_slot(path).unwrap()
  assert_true(independent.try_acquire().unwrap())
  let progress = Ref(ControlClientPending)
  assert_false(retry_control_terminal_handles((client, slot), progress))
  assert_true(progress.val is ControlSlotUnknown)
  assert_true(client.response_limit() is Err(Closed))
  assert_false(retry_control_terminal_handles((client, slot), progress))
  assert_eq(independent.verify_current_hold(), Ok(()))
  assert_true(independent.close())
  // Returning this Library reference is separate from the unresolved Slot.
  library.close_checked().unwrap()
  assert_true(progress.val is ControlSlotUnknown)
}
