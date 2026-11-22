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
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 32L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let host = @resources.reserve_shared_capacity(ledger, 16L).unwrap()
  let pool = open_pool_on_vm_capacity(ledger, vm, 12L, 4, 6).unwrap()
  let cleanups = Ref(0)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    reserve_buffer(pool, 4, 1L, () => {
      cleanups.val += 1
      true
    })
    is Err(Resource(_)),
  )
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
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 36L,
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
test "consumed projection returns only transfer while an offered output remains live" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 8,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 512L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 256L).unwrap()
  let pool = open_pool_on_vm_capacity(ledger, vm, 206L, 6, 16).unwrap()
  let cleanup = Ref(false)
  let cleanup_calls = Ref(0)
  // Each output carries 32 bytes of Core wire, 32 bytes of physical copies,
  // and 5 bytes of retained physical control. Three original quotes need 207.
  let saved = reserve_output_buffer(pool, 16, 37L, () => {
    cleanup_calls.val += 1
    cleanup.val
  }).unwrap()
  let payload = reserve_output_buffer(pool, 16, 37L, () => true).unwrap()
  supply_buffer_output(pool, saved, b"saved").unwrap()
  supply_buffer_output(pool, payload, b"payload").unwrap()
  assert_true(
    reserve_output_buffer(pool, 16, 37L, () => true)
    is Err(Resource(@resources.RetentionLimit)),
  )
  let held = @resources.ledger_usage(ledger)
  let borrow = borrow_buffer(pool, saved, () => true).unwrap()
  assert_eq(retire_consumed_output_transport(pool, saved), Err(CleanupPending))
  assert_eq(buffer_wire(pool, saved), Some(b"saved"))
  assert_eq(@resources.ledger_usage(ledger), held)
  return_buffer_borrow(pool, borrow).unwrap()
  retire_consumed_output_transport(pool, saved).unwrap()
  let reduced = @resources.ledger_usage(ledger)
  assert_eq(
    reduced.reserved_execution_bytes,
    held.reserved_execution_bytes - 32L,
  )
  assert_eq(reduced.reserved_retention_bytes, held.reserved_retention_bytes)
  assert_eq(reduced.attempts, held.attempts)
  assert_eq(buffer_pool_usage(pool).allocated, 74L)
  assert_eq(buffer_pool_reserved(pool), 42L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 32L)
  assert_true(buffer_wire(pool, saved) is None)
  assert_true(supply_buffer_output(pool, saved, b"replacement") is Err(_))
  assert_true(retire_consumed_output_transport(pool, saved) is Err(_))
  assert_eq(buffer_wire(pool, payload), Some(b"payload"))
  assert_eq(cleanup_calls.val, 0)
  let next = reserve_output_buffer(pool, 16, 37L, () => true).unwrap()
  assert_eq(close_buffer(pool, saved), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 143L)
  assert_eq(buffer_pool_reserved(pool), 79L)
  cleanup.val = true
  close_buffer(pool, saved).unwrap()
  assert_eq(cleanup_calls.val, 2)
  close_buffer(pool, next).unwrap()
  close_buffer(pool, payload).unwrap()
  close_pool(pool).unwrap()
  assert_eq(buffer_pool_reserved(pool), 0L)
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 256L)
  @resources.close_shared_capacity(vm).unwrap()
  @resources.settle_shared_capacity(vm).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "refused physical copy reconciliation leaves the same slot and its outstanding charge" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 512L,
  }).unwrap()
  let vm = @resources.reserve_shared_capacity(ledger, 256L).unwrap()
  let pool = open_pool_on_vm_capacity(ledger, vm, 128L, 4, 16).unwrap()
  let stopped = Ref(false)
  let saved = reserve_output_buffer(pool, 16, 37L, () => stopped.val).unwrap()
  supply_buffer_output(pool, saved, b"consumed").unwrap()
  let original_copy = saved.copy_capacity.unwrap()
  // Keep a real claim on the copy reservation. The VM can return its wire,
  // but the second reconciliation must refuse to resize a non-idle owner.
  let outstanding = @resources.allocate_shared_capacity(original_copy, 1L).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(
    retire_consumed_output_transport(pool, saved),
    Err(Resource(@resources.ClosedHolding)),
  )
  assert_eq(@resources.shared_capacity_usage(vm).allocated, 0L)
  assert_eq(buffer_pool_usage(pool).allocated, 37L)
  assert_eq(buffer_pool_reserved(pool), 37L)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(physical_equal(saved.copy_capacity.unwrap(), original_copy))
  assert_true(buffer_wire(pool, saved) is None)
  assert_true(retire_consumed_output_transport(pool, saved) is Err(_))
  assert_eq(close_buffer(pool, saved), Err(CleanupPending))
  assert_eq(buffer_pool_usage(pool).allocated, 37L)
  assert_eq(buffer_pool_reserved(pool), 37L)
  assert_eq(@resources.ledger_usage(ledger), before)
  @resources.retire_shared_capacity(outstanding).unwrap()
  @resources.release_shared_capacity(outstanding).unwrap()
  stopped.val = true
  close_buffer(pool, saved).unwrap()
  assert_eq(buffer_pool_usage(pool).allocated, 0L)
  assert_eq(buffer_pool_reserved(pool), 0L)
  close_pool(pool).unwrap()
  @resources.close_shared_capacity(vm).unwrap()
  @resources.settle_shared_capacity(vm).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
}

///|
test "imported VM pools share original backing but close only their own suballocations" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 24L,
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
