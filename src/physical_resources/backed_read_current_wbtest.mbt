///|
// Same-Owner portable counters. No Native arena, FD or physical ACK is proved.
test "backed read current-only repeated checks preserve the same borrow and accounting" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let borrow = read_use.borrow.unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  for _ in 0..<4 {
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    ).unwrap()
  }
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(physical_equal(read_use.borrow.unwrap(), borrow))
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  let copied : BackedExecutionReadUse[Ref[Int], Ref[Int]] = { ..read_use, }
  assert_eq(
    require_backed_execution_read_use_current(
      region, provider, child, ticket, copied,
    ),
    Err(ForeignOriginal),
  )
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_true(borrow.returned)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(ledger_usage(ledger), before)
  assert_eq(
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    ),
    Err(ForeignOriginal),
  )
}

///|
test "backed read current-only retains the same Resource park refusal" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 16, 4, 4).unwrap()
  let capacity = reserve_shared_capacity(ledger, 80L).unwrap()
  let allocation = allocate_shared_capacity(capacity, 80L).unwrap()
  let provider = Ref(1)
  let region : BackedExecutionRegion[Ref[Int], Ref[Int]] = issue_backed_execution_region(
    capacity, allocation, provider,
  ).unwrap()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    ),
    Err(Resource(ResourceParked)),
  )
  assert_eq(
    stop_backed_execution_read_use(region, provider, child, ticket, read_use),
    Err(Resource(ResourceParked)),
  )
  assert_eq(
    return_backed_execution_read_use_after_owner_ack(
      region, provider, child, ticket, read_use,
    ),
    Err(Resource(ResourceParked)),
  )
  assert_false(read_use.closing)
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  resource_park_test_invalidate(park)
  require_backed_execution_read_use_current(
    region, provider, child, ticket, read_use,
  ).unwrap()
}
