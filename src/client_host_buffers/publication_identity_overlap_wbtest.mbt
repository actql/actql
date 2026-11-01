///|
test "fixed identity and full body preserve both original borrowers at unchanged pool allowance" {
  let pool = open_pool(12582912L, 128, 1048576).unwrap()
  // Independent remaining-capacity counter, not E's unrecorded numeric trace.
  // An already retained parent leaves room for the full body plus the exact
  // 71-byte identity, but not two full one-MiB output reservations.
  let parent = reserve_output_buffer(pool, 2, 5242880L, () => true).unwrap()
  supply_buffer_output(pool, parent, b"{}").unwrap()
  let parent_ready = Ref(false)
  let original = borrow_buffer(pool, parent, () => parent_ready.val).unwrap()
  let full = reserve_output_buffer(pool, 1048576, 2097352L, () => true).unwrap()
  assert_true(
    reserve_output_buffer(pool, 1048576, 2097352L, () => true)
    is Err(Resource(RetentionLimit)),
  )
  close_buffer(pool, full).unwrap()
  let identity_ready = Ref(false)
  let identity = reserve_output_buffer(pool, 71, 342L, () => identity_ready.val).unwrap()
  supply_buffer_output(
    pool, identity, b"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let identity_borrow = borrow_buffer(pool, identity, () => identity_ready.val).unwrap()
  let body = reserve_output_buffer(pool, 1048576, 2097352L, () => true).unwrap()
  supply_buffer_output(pool, body, b"{\"original\":true}").unwrap()
  assert_eq(buffer_pool_usage(pool).capacity, 12582912L)
  assert_eq(buffer_output_limit(pool, body), None)
  assert_eq(buffer_length(pool, identity), Some(71))
  assert_eq(close_buffer(pool, identity), Err(CleanupPending))
  assert_eq(close_buffer(pool, parent), Err(CleanupPending))
  close_buffer(pool, body).unwrap()
  assert_eq(return_buffer_borrow(pool, identity_borrow), Err(CleanupPending))
  identity_ready.val = true
  return_buffer_borrow(pool, identity_borrow).unwrap()
  close_buffer(pool, identity).unwrap()
  assert_eq(close_buffer(pool, parent), Err(CleanupPending))
  parent_ready.val = true
  return_buffer_borrow(pool, original).unwrap()
  close_buffer(pool, parent).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 0L)
  close_pool(pool).unwrap()
}
