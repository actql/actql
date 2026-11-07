///|
test "captured guard constructors have a separate fixed original control quote" {
  // Independently authored constructor vector: current/live closures 2H/8R,
  // optional live wrapper 1H/1R/1W. Borrowed originals add no payload storage.
  assert_eq(captured_local_tasks_control_units.record_headers, 3L)
  assert_eq(captured_local_tasks_control_units.reference_slots, 9L)
  assert_eq(captured_local_tasks_control_units.scalar_words, 1L)
  assert_eq(captured_local_tasks_control_units.owned_utf16_units, 0L)
  assert_eq(captured_local_tasks_control_units.owned_wire_bytes, 0L)
  let quote = captured_local_tasks_control_capacity().unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(quote), 128L)
  assert_eq(@execution.execution_capacity_execution_bytes(quote), 128L)
  // Existing per-output JS cleanup is a different owner and unchanged.
  assert_eq(client_local_cleanup_retained_bytes(), 584L)
  let limits = captured_tasks_requirements(captured_tasks_prepared()).unwrap()
  assert_eq(limits.maximum_limits().retained_bytes, 200000000L)
  assert_eq(limits.maximum_limits().execution_bytes, 536870912L)
  for missing in ["retained", "execution"] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: if missing == "retained" {
        127L
      } else {
        128L
      },
      execution_bytes: if missing == "execution" {
        127L
      } else {
        128L
      },
    }).unwrap()
    assert_true(@resources.reserve_capacity(ledger, 128L, 128L) is Err(_))
    let usage = @resources.ledger_usage(ledger)
    assert_eq(usage.attempts, 0)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
  }
}

///|
test "captured optional live guard retains the same funded original until cleanup" {
  let value = captured_tasks_fixture(simultaneous=true)
  assert_true(
    @resources.capacity_reservation_matches(
      value.controls_ledger,
      value.controls,
      128L,
      128L,
    ),
  )
  let checks = Ref(0)
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    64,
    100000,
    () => true,
    require_live=Some(() => {
      checks.val += 1
      true
    }),
  ).unwrap()
  assert_true(checks.val > 0)
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_true(execution.close())
  assert_true(@resources.capacity_reservation_open(value.controls))
  captured_tasks_close_source(value)
  assert_false(@resources.capacity_reservation_open(value.controls))
}
