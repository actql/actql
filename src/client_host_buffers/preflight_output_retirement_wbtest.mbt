///|
test "preflight transport retirement retains input borrower and original capacity formula" {
  let pool = open_pool(8388608L, 8, 1048576).unwrap()
  let input_stopped = Ref(false)
  let cleaned = Ref(false)
  let cleanup_calls = Ref(0)
  // Independently fixed original trace quantities: the other allocations
  // total 725007 bytes; the projection charges 2097200 + 2 * 1048576.
  let input = reserve_output_buffer(pool, 2, 725003L, () => true).unwrap()
  supply_buffer_output(pool, input, b"{}").unwrap()
  let original_input = borrow_buffer(pool, input, () => input_stopped.val).unwrap()
  let projection = reserve_output_buffer(pool, 1048576, 2097200L, fn() {
    cleanup_calls.val += 1
    cleaned.val
  }).unwrap()
  supply_buffer_output(pool, projection, b"original projection").unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 4919359L)
  assert_true(
    reserve_output_buffer(pool, 1048576, 2097200L, () => true)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(close_buffer(pool, projection), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 4919359L)
  assert_eq(close_buffer(pool, input), Err(CleanupPending))
  assert_eq(return_buffer_borrow(pool, original_input), Err(CleanupPending))
  cleaned.val = true
  close_buffer(pool, projection).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 725007L)
  assert_eq(buffer_length(pool, projection), None)
  close_buffer(pool, projection).unwrap()
  assert_eq(cleanup_calls.val, 2)
  assert_eq(close_buffer(pool, input), Err(CleanupPending))
  let publication = reserve_output_buffer(pool, 1048576, 2097200L, () => true).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 4919359L)
  close_buffer(pool, publication).unwrap()
  input_stopped.val = true
  return_buffer_borrow(pool, original_input).unwrap()
  close_buffer(pool, input).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 0L)
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 0L)
}
