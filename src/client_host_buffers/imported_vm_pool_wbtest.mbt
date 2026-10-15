///|
// Private capacity stand-ins. No child VM, provider, channel, FD or numerical
// profile is established by this portable accounting counter.
test "imported VM pool does not reserve the same fixed memory twice" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 32L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let host = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let before = @resources.ledger_usage(ledger)
  let pool = open_pool_on_vm_capacity(ledger, vm, 12L, 4, 6).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  let slot = reserve_output_buffer(pool, 4, 0L, () => true).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 8L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 8L)
  assert_eq(@resources.shared_capacity_usage(host).allocated, 0L)
  close_buffer(pool, slot).unwrap()
  close_pool(pool).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(@resources.shared_capacity_usage(vm).closing)
  assert_false(@resources.shared_capacity_usage(host).closing)
}

///|
test "imported VM pool rejects unfunded external copy before publishing it" {
  let ledger = @resources.create_ledger({
    planning_work: 0, attempts: 4, holdings: 0,
    transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 32L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let host = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let pool = open_pool_on_vm_capacity(ledger, vm, 12L, 4, 6).unwrap()
  let cleanups = Ref(0)
  let before = @resources.ledger_usage(ledger)
  assert_true(reserve_buffer(pool, 4, 1L, () => {
    cleanups.val += 1
    true
  }) is Err(Resource(_)))
  assert_eq(cleanups.val, 0)
  assert_eq(buffer_pool_usage(pool).allocated, 0L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 0L)
  assert_true(lookup_buffer(pool, 1) is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  close_pool(pool).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_false(@resources.shared_capacity_usage(host).closing)
}

///|
test "imported VM pool external copy retains independent capacity until physical cleanup" {
  let ledger = @resources.create_ledger({
    planning_work: 0, attempts: 4, holdings: 0,
    transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 36L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let host = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let pool = open_pool_on_vm_capacity(ledger, vm, 12L, 4, 6).unwrap()
  let stopped = Ref(false)
  let cleaned = Ref(false)
  let cleanups = Ref(0)
  let slot = reserve_output_buffer(pool, 4, 4L, () => {
    cleanups.val += 1
    cleaned.val
  }).unwrap()
  supply_buffer_output(pool, slot, b"null").unwrap()
  let borrow = borrow_buffer(pool, slot, () => stopped.val).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 36L)
  assert_eq(buffer_pool_reserved(pool), 4L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 8L)
  assert_eq(@resources.shared_capacity_usage(host).allocated, 0L)
  assert_true(reserve_buffer(pool, 1, 0L, () => true) is Err(Resource(_)))
  assert_eq(close_pool(pool), Err(CleanupPending))
  assert_eq(cleanups.val, 0)
  assert_eq(return_buffer_borrow(pool, borrow), Err(CleanupPending))
  stopped.val = true
  return_buffer_borrow(pool, borrow).unwrap()
  assert_eq(close_pool(pool), Err(CleanupPending))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 36L)
  assert_eq(buffer_pool_usage(pool).allocated, 12L)
  cleaned.val = true
  close_pool(pool).unwrap()
  close_pool(pool).unwrap()
  assert_eq(cleanups.val, 2)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 32L)
  assert_eq(buffer_pool_reserved(pool), 0L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 0L)
  assert_false(@resources.shared_capacity_usage(vm).closing)
  assert_false(@resources.shared_capacity_usage(host).closing)
}

///|
test "imported VM pools share original backing but close only their own suballocations" {
  let ledger = @resources.create_ledger({
    planning_work: 0, attempts: 2, holdings: 0,
    transfer_bytes: 0L, retained_bytes: 0L, execution_bytes: 24L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let host = @resources.reserve_shared_capacity(ledger, 8L).unwrap()
  let left = open_pool_on_vm_capacity(ledger, vm, 12L, 4, 6).unwrap()
  let right = open_pool_on_vm_capacity(ledger, vm, 12L, 4, 6).unwrap()
  let l = reserve_output_buffer(left, 4, 0L, () => true).unwrap()
  let r = reserve_output_buffer(right, 4, 0L, () => true).unwrap()
  assert_true(reserve_buffer(left, 1, 0L, () => true) is Err(Resource(_)))
  close_buffer(left, l).unwrap()
  close_pool(left).unwrap()
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 8L)
  assert_true(lookup_buffer(right, buffer_serial(r)) is Some(_))
  close_pool(right).unwrap()
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 24L)
  assert_false(@resources.shared_capacity_usage(vm).closing)
  assert_false(@resources.shared_capacity_usage(host).closing)
}
