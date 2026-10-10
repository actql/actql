///|
test "concurrent copies share one capacity and cleanup failure retains the same lease" {
  let pool = open_pool(20L, 4, 16).unwrap()
  let calls = Ref(0)
  let stopped = Ref(false)
  let first = reserve_buffer(pool, 4, 8L, fn() {
    calls.val += 1
    stopped.val
  }).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 16L)
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 20L)
  assert_true(
    reserve_buffer(pool, 4, 8L, () => true) is Err(Resource(RetentionLimit)),
  )
  assert_eq(close_buffer(pool, first), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 16L)
  assert_true(lookup_buffer(pool, buffer_serial(first)) is Some(_))
  assert_true(
    reserve_buffer(pool, 4, 8L, () => true) is Err(Resource(RetentionLimit)),
  )
  stopped.val = true
  close_buffer(pool, first).unwrap()
  close_buffer(pool, first).unwrap()
  assert_eq(calls.val, 2)
  assert_eq(buffer_pool_usage(pool).allocated, 0L)
  assert_true(lookup_buffer(pool, buffer_serial(first)) is None)
  let next = reserve_buffer(pool, 4, 8L, () => true).unwrap()
  assert_true(buffer_serial(next) != buffer_serial(first))
  close_pool(pool).unwrap()
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 0L)
}

///|
test "retirement cannot free a borrowed copy until physical stop and cleanup succeed" {
  let pool = open_pool(64L, 4, 32).unwrap()
  let input = b"{\"n\":null}"
  let cleanups = Ref(0)
  let slot = reserve_buffer(pool, input.length(), 16L, fn() {
    cleanups.val += 1
    true
  }).unwrap()
  fill_buffer(pool, slot, 0, input.length(), index => Some(input[index])).unwrap()
  seal_buffer(pool, slot, 10, 4).unwrap()
  let physically_stopped = Ref(false)
  let borrow = borrow_buffer(pool, slot, () => physically_stopped.val).unwrap()
  assert_eq(close_pool(pool), Err(CleanupPending))
  assert_eq(cleanups.val, 0)
  assert_eq(buffer_pool_usage(pool).allocated, 36L)
  assert_eq(return_buffer_borrow(pool, borrow), Err(CleanupPending))
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 64L)
  physically_stopped.val = true
  return_buffer_borrow(pool, borrow).unwrap()
  return_buffer_borrow(pool, borrow).unwrap()
  close_pool(pool).unwrap()
  assert_eq(cleanups.val, 1)
  assert_eq(buffer_pool_ledger_usage(pool).reserved_execution_bytes, 0L)
}

///|
test "foreign owners overlap and incomplete input do not invoke transfer callbacks" {
  let left = open_pool(64L, 4, 32).unwrap()
  let right = open_pool(64L, 4, 32).unwrap()
  let slot = reserve_buffer(left, 4, 4L, () => true).unwrap()
  let reads = Ref(0)
  let read = fn(index) {
    reads.val += 1
    Some(b"null"[index])
  }
  assert_eq(fill_buffer(right, slot, 0, 4, read), Err(ForeignOwner))
  assert_eq(fill_buffer(left, slot, 1, 3, read), Err(InvalidPosition))
  assert_eq(seal_buffer(left, slot, 4, 4), Err(Incomplete))
  assert_eq(reads.val, 0)
  fill_buffer(left, slot, 0, 2, read).unwrap()
  assert_eq(fill_buffer(left, slot, 0, 2, read), Err(InvalidPosition))
  fill_buffer(left, slot, 2, 2, read).unwrap()
  seal_buffer(left, slot, 4, 4).unwrap()
  assert_eq(fill_buffer(left, slot, 4, 0, read), Err(Closed))
  assert_eq(reads.val, 4)
  assert_true(buffer_source(right, slot) is None)
  assert_eq(close_buffer(right, slot), Err(ForeignOwner))
  close_pool(left).unwrap()
  close_pool(right).unwrap()
}

///|
test "descriptor quota covers simultaneous borrowers as well as input slots" {
  let pool = open_pool(64L, 2, 16).unwrap()
  let slot = reserve_buffer(pool, 4, 4L, () => true).unwrap()
  fill_buffer(pool, slot, 0, 4, index => Some(b"null"[index])).unwrap()
  seal_buffer(pool, slot, 4, 4).unwrap()
  let borrowed = borrow_buffer(pool, slot, () => true).unwrap()
  assert_true(borrow_buffer(pool, slot, () => true) is Err(Capacity))
  assert_true(reserve_buffer(pool, 4, 4L, () => true) is Err(Capacity))
  return_buffer_borrow(pool, borrowed).unwrap()
  let second = reserve_buffer(pool, 4, 4L, () => true).unwrap()
  assert_true(buffer_serial(second) != buffer_serial(slot))
  close_pool(pool).unwrap()
}

///|
test "preserved source values distinguish raw Unicode NULL and absence" {
  let input = @utf8.encode(
    "{\"e\u0301/~😀\":\"line\\r\\n😀\",\"nullable\":null}",
  )
  let pool = open_pool(1024L, 4, 512).unwrap()
  let slot = reserve_buffer(pool, input.length(), input.length().to_int64(), () => {
    true
  }).unwrap()
  fill_buffer(pool, slot, 0, input.length(), index => Some(input[index])).unwrap()
  seal_buffer(pool, slot, 10, 8).unwrap()
  guard buffer_source(pool, slot) is Some({ value: Object(fields), .. }) else {
    fail("Expected the original structured object")
  }
  assert_eq(fields.length(), 2)
  assert_eq(fields[0].key, "e\u0301/~😀")
  assert_true(fields[0].value.value is String("line\r\n😀"))
  assert_eq(fields[1].key, "nullable")
  assert_true(fields[1].value.value is Null)
  assert_true(!fields.iter().any(field => field.key == "absent"))
  close_pool(pool).unwrap()
}

///|
test "bad callback bytes and decode budget remain distinct from completed input" {
  let pool = open_pool(128L, 4, 32).unwrap()
  let slot = reserve_buffer(pool, 4, 4L, () => true).unwrap()
  assert_eq(
    fill_buffer(pool, slot, 0, 4, index => {
      if index == 2 {
        None
      } else {
        Some(b"null"[index])
      }
    }),
    Err(InvalidByte),
  )
  assert_eq(seal_buffer(pool, slot, 4, 4), Err(Incomplete))
  assert_true(buffer_source(pool, slot) is None)
  let second = reserve_buffer(pool, 5, 5L, () => true).unwrap()
  fill_buffer(pool, second, 0, 5, index => Some(b"[1,2]"[index])).unwrap()
  assert_true(
    seal_buffer(pool, second, 2, 4) is Err(Input({ issue: NodeLimit, .. })),
  )
  assert_true(buffer_source(pool, second) is None)
  assert_eq(buffer_pool_usage(pool).allocated, 27L)
  close_pool(pool).unwrap()
}
