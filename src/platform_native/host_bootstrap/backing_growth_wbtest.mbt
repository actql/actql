///|
test "Native root grows actual backing beyond initial acquisition on same ledger" {
  let original : BootstrapTestOriginal = { identity: 901, }
  let page = test_page_bytes_ffi()
  let supplier = prepare_installed_arena_supplier(
    original,
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    16L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 64L * page,
    },
    65536L,
  ).unwrap()
  let host = match supplier.acquire(original).unwrap() {
    Acquired(host) => host
    Pending(_, _) => abort("fixture acquisition failed")
  }
  host.claim(original, supplier.source, supplier.recipe, 1L).unwrap()
  let old = host.allocate(original, 8L * page).unwrap()
  let old_borrow = host.borrow(original, old).unwrap()
  let scope = host.borrow_backing(original).unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let ledger = host.ledger
  let capacity = host.capacity
  host.grow_backing(original, scope, 48L * page).unwrap()
  assert_true(physical_equal(host.ledger, ledger))
  assert_true(physical_equal(host.capacity, capacity))
  assert_eq(host.capacity_usage().capacity, 48L * page)
  assert_eq(backing_capacity_bytes_ffi(host.backing), 48L * page)
  assert_eq(host.usage().reserved_execution_bytes, 48L * page)
  let newer = host.allocate(original, 20L * page).unwrap()
  let newer_borrow = host.borrow(original, newer).unwrap()
  let usage = host.usage()
  assert_true(
    host.grow_backing(original, scope, 80L * page)
    is Err(Resource(ExecutionLimit)),
  )
  assert_eq(host.usage(), usage)
  assert_eq(backing_capacity_bytes_ffi(host.backing), 48L * page)
  host.grow_backing(original, scope, 48L * page).unwrap()
  assert_eq(host.usage(), usage)
  host.leave_borrow_scope(original, scope).unwrap()
  host.return_borrow(original, scope).unwrap()
  assert_eq(host.try_close(original), Err(ReadersPending))
  host.return_borrow(original, old_borrow).unwrap()
  assert_eq(host.try_close(original), Err(ReadersPending))
  host.return_borrow(original, newer_borrow).unwrap()
  host.try_close(original).unwrap()
  assert_eq(host.usage().reserved_execution_bytes, 0L)
}
