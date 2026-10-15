///|
// Portable same-Owner checks, not a Native arena/worker/FD or heap upper bound.
test "backed current-only keeps the original ticket usage and description unchanged" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  for _ in 0..<3 {
    check_backed_execution_delegation_current(region, provider, child, ticket).unwrap()
  }
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(
    backed_execution_delegation_description(region, provider, child, ticket).unwrap(),
    (backed_test_extent(), ExclusiveWrite, backed_test_limits()),
  )
}

///|
test "backed current-only rejects foreign provider child copied ticket and region" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let before = ledger_usage(ledger)
  let copied : BackedExecutionDelegation[Ref[Int], Ref[Int]] = { ..ticket, }
  let (_, _, _, other_provider, other_region) = backed_test_region()
  for (selected_region, selected_provider, selected_child, selected_ticket) in [
    (region, Ref(1), child, ticket),
    (region, provider, Ref(2), ticket),
    (region, provider, child, copied),
    (other_region, other_provider, child, ticket),
  ] {
    assert_eq(
      check_backed_execution_delegation_current(
        selected_region, selected_provider, selected_child, selected_ticket,
      ),
      Err(ForeignOriginal),
    )
  }
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
}

///|
test "backed current-only preserves entered cleanup during graceful closing and rejects retirement" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  assert_false(close_backed_execution_region(region, provider).unwrap())
  check_backed_execution_delegation_current(region, provider, child, ticket).unwrap()
  assert_true(
    reserve_backed_execution_delegation(
      region, provider, Ref(3), backed_test_extent(), ExclusiveWrite,
      backed_test_limits(), 0L, 0L,
    )
    is Err(RegionClosing),
  )
  let before = ledger_usage(ledger)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  check_backed_execution_delegation_current(region, provider, child, ticket).unwrap()
  assert_eq(ledger_usage(ledger), before)
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_eq(
    check_backed_execution_delegation_current(region, provider, child, ticket),
    Err(ForeignOriginal),
  )
  assert_true(close_backed_execution_region(region, provider).unwrap())
  // Closing clears the original provider first; preserve that refusal class.
  assert_eq(
    check_backed_execution_delegation_current(region, provider, child, ticket),
    Err(ForeignOriginal),
  )
}

///|
test "backed current-only rejects an already returned original borrow" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let borrow = ticket.borrow.unwrap()
  let before = ledger_usage(ledger)
  // Private state counter only; no physical return/stop is manufactured.
  borrow.returned = true
  assert_eq(
    check_backed_execution_delegation_current(region, provider, child, ticket),
    Err(Retired),
  )
  assert_true(
    backed_execution_delegation_description(region, provider, child, ticket)
    is Err(Retired),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
}

///|
test "backed current-only preserves the original Resource park fence" {
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
  let (_, consumer) = resource_park_test_consumer(identity, origin)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(
    check_backed_execution_delegation_current(region, provider, child, ticket),
    Err(Resource(ResourceParked)),
  )
  assert_true(
    backed_execution_delegation_description(region, provider, child, ticket)
    is Err(Resource(ResourceParked)),
  )
  assert_eq(ledger_usage(ledger), before)
  // Existing private test-only invalidation; not a COMMIT/physical ACK issuer.
  resource_park_test_invalidate(park)
  check_backed_execution_delegation_current(region, provider, child, ticket).unwrap()
}
