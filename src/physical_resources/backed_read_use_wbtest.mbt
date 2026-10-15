///|
// Portable Resource-owner counters only. The physical ACK calls are stand-ins;
// these tests do not execute a Root/Reader, fund a VM or admit a public profile.
fn backed_read_test_ticket(
  region : BackedExecutionRegion[Ref[Int], Ref[Int]],
  provider : Ref[Int],
  child : Ref[Int],
  access? : BackedExecutionAccess = ExclusiveWrite,
) -> BackedExecutionDelegation[Ref[Int], Ref[Int]] {
  reserve_backed_execution_delegation(
    region,
    provider,
    child,
    backed_test_extent(),
    access,
    backed_test_limits(),
    5L,
    7L,
  ).unwrap()
}

///|
test "backed read use borrows the exact original bytes without a second reserve" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let before = ledger_usage(ledger)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  require_backed_execution_read_use_current(
    region, provider, child, ticket, read_use,
  ).unwrap()
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_true(read_use.ticket is None && read_use.borrow is None)
  assert_true(ticket.read_use is None)
  assert_true(ticket.logical.unwrap().reservation.open)
}

///|
test "backed read use rejects same-valued foreign provider child and ticket" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    require_backed_execution_read_use_current(
      region,
      Ref(1),
      child,
      ticket,
      read_use,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    return_backed_execution_read_use_after_owner_ack(
      region,
      provider,
      Ref(2),
      ticket,
      read_use,
    )
    is Err(ForeignOriginal),
  )
  let (_, _, _, other_provider, other_region) = backed_test_region()
  let other_child = Ref(2)
  let other = backed_read_test_ticket(other_region, other_provider, other_child)
  assert_true(
    require_backed_execution_read_use_current(
      other_region, other_provider, other_child, other, read_use,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
}

///|
test "backed read use is one shot and repeated return cannot release the parent borrow" {
  let (_, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  assert_true(
    borrow_backed_execution_read_use(region, provider, child, ticket)
    is Err(ReadUseAlreadyIssued),
  )
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_true(
    borrow_backed_execution_read_use(region, provider, child, ticket)
    is Err(ReadUseAlreadyIssued),
  )
  assert_true(
    return_backed_execution_read_use_after_owner_ack(
      region, provider, child, ticket, read_use,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(shared_allocation_usage(allocation).readers, 2)
}

///|
test "backed read use pending cleanup fences parent settlement and keeps the same loan" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let before = ledger_usage(ledger)
  stop_backed_execution_read_use(region, provider, child, ticket, read_use).unwrap()
  stop_backed_execution_read_use(region, provider, child, ticket, read_use).unwrap()
  assert_true(
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    )
    is Err(RegionClosing),
  )
  assert_true(
    settle_backed_execution_after_owner_ack(
      region,
      provider,
      child,
      ticket,
      None,
    )
    is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(shared_allocation_usage(allocation).readers, 3)
  assert_true(ticket.logical.unwrap().reservation.open)
  // Only the existing physical Owner's later, actual same-context ACK returns
  // this read use. The parent still has its independent settlement duty.
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(ledger_usage(ledger), before)
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_eq(shared_allocation_usage(allocation).readers, 1)
}

///|
test "backed read use cleanup remains possible after region closing without freeing the arena" {
  let (ledger, capacity, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  assert_false(close_backed_execution_region(region, provider).unwrap())
  assert_true(
    require_backed_execution_read_use_current(
      region, provider, child, ticket, read_use,
    )
    is Err(RegionClosing),
  )
  stop_backed_execution_read_use(region, provider, child, ticket, read_use).unwrap()
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 87L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 5L)
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_true(close_backed_execution_region(region, provider).unwrap())
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "backed read use refuses readonly backing and closing before claiming" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child, access=ReadOnly)
  let before = ledger_usage(ledger)
  assert_true(
    borrow_backed_execution_read_use(region, provider, child, ticket)
    is Err(InvalidExtent),
  )
  assert_false(ticket.read_use_issued)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(ledger_usage(ledger), before)
  assert_false(close_backed_execution_region(region, provider).unwrap())
  assert_true(
    borrow_backed_execution_read_use(region, provider, child, ticket)
    is Err(RegionClosing),
  )
}

///|
test "backed read use retirement does not erase cumulative reports or unknown remainder" {
  let (ledger, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read_use = borrow_backed_execution_read_use(
    region, provider, child, ticket,
  ).unwrap()
  let usage = {
    ..ledger_usage(create_ledger(backed_test_limits()).unwrap()),
    planning_work: 2,
    transferred_bytes: 4L,
    uncertain_transfer_bytes: 1L,
    peak_retention_bytes: 3L,
  }
  report_backed_execution_delegation(region, provider, child, ticket, usage).unwrap()
  let before = ledger_usage(ledger)
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read_use,
  ).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ticket.peak_retention, 3L)
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 4L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 6L)
  assert_eq(ledger_usage(ledger).planning_work, 4)
}
