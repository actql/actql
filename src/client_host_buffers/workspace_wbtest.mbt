///|
test "workspace stop and cleanup independently retain the exact root reservation" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 3,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 100L,
  }).unwrap()
  let stopped = Ref(false)
  let cleaned = Ref(false)
  let stop_calls = Ref(0)
  let cleanup_calls = Ref(0)
  let workspace = reserve_workspace(
    ledger,
    75L,
    () => {
      stop_calls.val += 1
      stopped.val
    },
    () => {
      cleanup_calls.val += 1
      cleaned.val
    },
  ).unwrap()
  let pool = open_pool_on_ledger(ledger, 25L, 2, 16).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_eq(close_workspace(workspace), Err(CleanupPending))
  assert_eq(stop_calls.val, 1)
  assert_eq(cleanup_calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_true(open_pool_on_ledger(ledger, 1L, 2, 16) is Err(Resource(_)))
  stopped.val = true
  assert_eq(close_workspace(workspace), Err(CleanupPending))
  assert_eq(stop_calls.val, 2)
  assert_eq(cleanup_calls.val, 1)
  close_pool(pool).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 75L)
  cleaned.val = true
  close_workspace(workspace).unwrap()
  close_workspace(workspace).unwrap()
  assert_eq(stop_calls.val, 2)
  assert_eq(cleanup_calls.val, 2)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "workspace cleanup cannot acknowledge a missing physical stop" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 10L,
  }).unwrap()
  let stopped = Ref(false)
  let cleanup_calls = Ref(0)
  let workspace = reserve_workspace(ledger, 10L, () => stopped.val, () => {
    cleanup_calls.val += 1
    true
  }).unwrap()
  assert_eq(close_workspace(workspace), Err(CleanupPending))
  assert_eq(cleanup_calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 10L)
  stopped.val = true
  close_workspace(workspace).unwrap()
  assert_eq(cleanup_calls.val, 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "workspace capacity refusal precedes physical callbacks" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 10L,
  }).unwrap()
  let calls = Ref(0)
  let observe = () => {
    calls.val += 1
    true
  }
  assert_true(
    reserve_workspace(ledger, 0L, observe, observe) is Err(Resource(_)),
  )
  assert_true(
    reserve_workspace(ledger, 11L, observe, observe) is Err(Resource(_)),
  )
  assert_eq(calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
