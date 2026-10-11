///|
test "Core output reserves before production and does not become authoring input" {
  let pool = open_pool(128L, 4, 64).unwrap()
  let stopped = Ref(false)
  let calls = Ref(0)
  let slot = reserve_output_buffer(pool, 32, 64L, fn() {
    calls.val += 1
    stopped.val
  }).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 128L)
  assert_eq(buffer_length(pool, slot), None)
  assert_eq(buffer_output_limit(pool, slot), Some(32))
  assert_true(
    reserve_output_buffer(pool, 1, 0L, () => true)
    is Err(Resource(RetentionLimit)),
  )
  let reads = Ref(0)
  assert_eq(
    fill_buffer(pool, slot, 0, 1, fn(_) {
      reads.val += 1
      Some(0)
    }),
    Err(Closed),
  )
  assert_eq(reads.val, 0)
  assert_eq(seal_buffer(pool, slot, 4, 4), Err(Closed))
  let original = @utf8.encode("e\u0301/~😀\r\nNULL")
  supply_buffer_output(pool, slot, original).unwrap()
  assert_eq(buffer_wire(pool, slot), Some(original))
  assert_eq(buffer_length(pool, slot), Some(15))
  assert_true(buffer_source(pool, slot) is None)
  assert_eq(buffer_byte(pool, slot, 14), Some(b"L"[0]))
  assert_eq(buffer_byte(pool, slot, 15), None)
  assert_eq(buffer_output_limit(pool, slot), None)
  assert_eq(supply_buffer_output(pool, slot, b"replacement"), Err(Closed))
  assert_eq(close_buffer(pool, slot), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 128L)
  assert_eq(buffer_wire(pool, slot), None)
  stopped.val = true
  close_buffer(pool, slot).unwrap()
  close_buffer(pool, slot).unwrap()
  assert_eq(calls.val, 2)
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 0L)
}

///|
test "output overflow foreign ownership and input slots cannot publish bytes" {
  let left = open_pool(64L, 4, 32).unwrap()
  let right = open_pool(64L, 4, 32).unwrap()
  let output = reserve_output_buffer(left, 4, 0L, () => true).unwrap()
  let input = reserve_buffer(left, 4, 0L, () => true).unwrap()
  assert_eq(supply_buffer_output(right, output, b"null"), Err(ForeignOwner))
  assert_eq(supply_buffer_output(left, input, b"null"), Err(InvalidLimits))
  assert_eq(supply_buffer_output(left, output, b"12345"), Err(InvalidLimits))
  assert_eq(buffer_length(left, output), None)
  assert_eq(buffer_pool_usage(left).allocated, 16L)
  supply_buffer_output(left, output, b"").unwrap()
  assert_eq(buffer_length(left, output), Some(0))
  assert_eq(buffer_byte(left, output, 0), None)
  assert_true(buffer_source(left, output) is None)
  close_pool(left).unwrap()
  close_pool(right).unwrap()
}

///|
test "output retirement retains physical readers and cleanup under the same reservation" {
  let pool = open_pool(64L, 4, 32).unwrap()
  let cleaned = Ref(false)
  let stopped = Ref(false)
  let slot = reserve_output_buffer(pool, 20, 16L, () => cleaned.val).unwrap()
  supply_buffer_output(pool, slot, b"opaque Core record").unwrap()
  let reader = borrow_buffer(pool, slot, () => stopped.val).unwrap()
  assert_eq(close_pool(pool), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 56L)
  assert_eq(return_buffer_borrow(pool, reader), Err(CleanupPending))
  stopped.val = true
  return_buffer_borrow(pool, reader).unwrap()
  assert_eq(close_pool(pool), Err(CleanupPending))
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 64L)
  cleaned.val = true
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 0L)
}
