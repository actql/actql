///|
test "completed publication transport retirement preserves original borrower at traced capacity" {
  let pool = open_pool(8388608L, 8, 1048576).unwrap()
  let stop_ready = Ref(false)
  let cleanup_ready = Ref(false)
  let cleanups = Ref(0)
  // Independent trace: 5175380 allocated includes one 4194352-byte projection.
  // The same candidate needs 4194352; two such projections alone exceed the
  // original pool by 96 bytes. No capacity or charge is weakened here.
  let original = reserve_output_buffer(pool, 2, 981024L, () => true).unwrap()
  supply_buffer_output(pool, original, b"{}").unwrap()
  let borrow = borrow_buffer(pool, original, () => stop_ready.val).unwrap()
  let projection = reserve_output_buffer(pool, 1048576, 2097200L, fn() {
    cleanups.val += 1
    cleanup_ready.val
  }).unwrap()
  supply_buffer_output(pool, projection, b"completed wire").unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 5175380L)
  assert_true(
    reserve_output_buffer(pool, 1048576, 2097200L, () => true)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(close_buffer(pool, projection), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 5175380L)
  assert_eq(close_buffer(pool, original), Err(CleanupPending))
  cleanup_ready.val = true
  close_buffer(pool, projection).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 981028L)
  assert_eq(buffer_length(pool, projection), None)
  close_buffer(pool, projection).unwrap()
  assert_eq(cleanups.val, 2)
  let candidate = reserve_output_buffer(pool, 1048576, 2097200L, () => true).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 5175380L)
  assert_eq(close_buffer(pool, original), Err(CleanupPending))
  close_buffer(pool, candidate).unwrap()
  assert_eq(return_buffer_borrow(pool, borrow), Err(CleanupPending))
  stop_ready.val = true
  return_buffer_borrow(pool, borrow).unwrap()
  close_buffer(pool, original).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 0L)
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 0L)
}
