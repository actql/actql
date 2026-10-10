///|
test "transfer pool cannot independently spend workspace reserved on the same root" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 3,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 100L,
  }).unwrap()
  let workspace = @resources.reserve_attempt(ledger, 0L, 0L, 70L).unwrap()
  assert_true(open_pool_on_ledger(ledger, 31L, 4, 16) is Err(Resource(_)))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 70L)
  let pool = open_pool_on_ledger(ledger, 30L, 4, 16).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_eq(buffer_pool_reserved(pool), 30L)
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_reserved(pool), 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 70L)
  assert_true(@resources.reservation_open(workspace))
  @resources.settle_reservation(ledger, workspace).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "overlapping pools retain cleanup obligations on the shared root" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 3,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 100L,
  }).unwrap()
  let left = open_pool_on_ledger(ledger, 60L, 4, 16).unwrap()
  let right = open_pool_on_ledger(ledger, 40L, 4, 16).unwrap()
  let cleaned = Ref(false)
  let slot = reserve_buffer(left, 4, 8L, () => cleaned.val).unwrap()
  assert_eq(close_pool(left), Err(CleanupPending))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_true(open_pool_on_ledger(ledger, 1L, 4, 16) is Err(Resource(_)))
  close_pool(right).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 60L)
  assert_eq(buffer_pool_usage(left).allocated, 16L)
  cleaned.val = true
  close_buffer(left, slot).unwrap()
  close_pool(left).unwrap()
  close_pool(left).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "invalid composed pool does not reserve root capacity" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 10L,
  }).unwrap()
  assert_true(open_pool_on_ledger(ledger, 1L, 0, 16) is Err(InvalidLimits))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  let valid = open_pool_on_ledger(ledger, 10L, 2, 16).unwrap()
  close_pool(valid).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
