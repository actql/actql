///|
test "original allocation charge observes physical rounding without reserving or proving availability" {
  let original = { identity: 301, }
  let host = test_host(original)
  let page = test_page_bytes_ffi()
  let ledger = host.usage()
  let capacity = host.capacity_usage()
  assert_eq(host.allocation_charge(original, 1L), Ok(page))
  assert_eq(host.allocation_charge(original, page), Ok(page))
  assert_eq(host.allocation_charge(original, page + 1L), Ok(2L * page))
  assert_eq(host.usage(), ledger)
  assert_eq(host.capacity_usage().allocated, capacity.allocated)
  assert_eq(host.capacity_usage().capacity, capacity.capacity)
  // The physical charge is unchanged even when no allocation can be admitted.
  let allocation = host
    .allocate(original, capacity.capacity - capacity.allocated)
    .unwrap()
  assert_eq(host.capacity_usage().allocated, capacity.capacity)
  let full_ledger = host.usage()
  assert_eq(host.allocation_charge(original, 1L), Ok(page))
  assert_eq(host.usage(), full_ledger)
  assert_eq(host.capacity_usage().allocated, capacity.capacity)
  assert_true(host.allocate(original, 1L) is Err(_))
  host.retire(original, allocation).unwrap()
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}

///|
test "original allocation charge refuses foreign unclaimed and invalid inputs without changing custody" {
  let original = { identity: 302, }
  let foreign = { identity: 302, }
  let page = test_page_bytes_ffi()
  let supplier = test_supplier(original, 64L * page)
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("fixture physical backing unavailable")
  }
  assert_true(host.allocation_charge(foreign, 1L) is Err(ForeignOriginal))
  assert_true(host.allocation_charge(original, 1L) is Err(Unavailable))
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let ledger = host.usage()
  let allocated = host.capacity_usage().allocated
  assert_true(host.allocation_charge(original, 0L) is Err(Unavailable))
  assert_true(host.allocation_charge(original, -1L) is Err(Unavailable))
  assert_true(
    host.allocation_charge(original, 9223372036854775807L) is Err(Unavailable),
  )
  assert_true(
    host.allocation_charge(original, 64L * page + 1L) is Err(Unavailable),
  )
  assert_eq(host.usage(), ledger)
  assert_eq(host.capacity_usage().allocated, allocated)
  host.try_close(original).unwrap()
}

///|
test "closing allocation charge cannot acknowledge pending original backing cleanup" {
  let original = { identity: 303, }
  let host = test_host(original)
  let borrowed = host.borrow_backing(original).unwrap()
  assert_true(host.try_close(original) is Err(ReadersPending))
  let ledger = host.usage()
  let allocated = host.capacity_usage().allocated
  assert_true(host.allocation_charge(original, 1L) is Err(Closing))
  assert_eq(host.usage(), ledger)
  assert_eq(host.capacity_usage().allocated, allocated)
  assert_true(host.usage().reserved_execution_bytes > 0L)
  assert_false(host.closed)
  host.return_borrow(original, borrowed).unwrap()
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
  assert_true(host.allocation_charge(original, 1L) is Err(Closing))
}
