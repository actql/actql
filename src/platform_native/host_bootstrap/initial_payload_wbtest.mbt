///|
test "initial payload candidate observes charged control and cannot be reused after allocation retirement" {
  let original = { identity: 81, }
  let host = test_host(original)
  let before = host.capacity_usage()
  let bytes = host.initial_payload_capacity(original).unwrap()
  assert_true(before.allocated > 0L && bytes > 0L)
  assert_eq(bytes, before.capacity - before.allocated)
  assert_eq(host.capacity_usage().allocated, before.allocated)
  assert_eq(host.capacity_usage().capacity, before.capacity)
  assert_eq(host.capacity_usage().closing, before.closing)
  let allocation = host.allocate(original, bytes).unwrap()
  assert_eq(host.capacity_usage().allocated, before.capacity)
  assert_true(host.initial_payload_capacity(original) is Err(AlreadyConsumed))
  host.retire(original, allocation).unwrap()
  assert_eq(host.capacity_usage().allocated, before.allocated)
  assert_true(host.initial_payload_capacity(original) is Err(AlreadyConsumed))
  host.try_close(original).unwrap()
}

///|
test "initial payload candidate keeps original and closing fences" {
  let original = { identity: 82, }
  let foreign = { identity: 82, }
  let host = test_host(original)
  assert_true(host.initial_payload_capacity(foreign) is Err(ForeignOriginal))
  let scope = host.borrow_backing(original).unwrap()
  assert_true(host.try_close(original) is Err(ReadersPending))
  assert_true(host.initial_payload_capacity(original) is Err(Closing))
  host.return_borrow(original, scope).unwrap()
  host.try_close(original).unwrap()
  assert_true(host.initial_payload_capacity(original) is Err(Closing))
}

///|
test "accounting remainder does not promise absence of other physical allocations" {
  let original = { identity: 83, }
  let host = test_host(original)
  // Independent fault counter: physical occupancy not represented by a
  // Bootstrap child. It must not be inferred zero from logical usage.
  let occupied = allocate_ffi(host.backing, test_page_bytes_ffi())
  assert_eq(extent_status_ffi(occupied), 0)
  let candidate = host.initial_payload_capacity(original).unwrap()
  assert_true(host.allocate(original, candidate) is Err(Physical(_)))
  assert_eq(host.children.length(), 1)
  assert_false(host.children[0].released)
  assert_true(host.initial_payload_capacity(original) is Err(AlreadyConsumed))
  assert_eq(retire_ffi(host.backing, occupied), 0)
  host.try_close(original).unwrap()
  assert_true(host.children.is_empty() && host.closed)
}
