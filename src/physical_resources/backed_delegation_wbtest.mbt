///|
// Portable identity/accounting vectors. Owner-ACK calls stand in for the
// trusted physical adapter; these are not worker/FD/VM/numerical acceptance.
fn backed_test_region() -> (Ledger, SharedCapacity, SharedAllocation, Ref[Int], BackedExecutionRegion[Ref[Int], Ref[Int]]) {
  let ledger = create_ledger({ planning_work: 50, attempts: 20, holdings: 20,
    transfer_bytes: 100L, retained_bytes: 64L, execution_bytes: 100L, }).unwrap()
  let capacity = reserve_shared_capacity(ledger, 80L).unwrap()
  let allocation = allocate_shared_capacity(capacity, 80L).unwrap()
  let provider = Ref(1)
  let region : BackedExecutionRegion[Ref[Int], Ref[Int]] =
    issue_backed_execution_region(capacity, allocation, provider).unwrap()
  (ledger, capacity, allocation, provider, region)
}

///|
fn backed_test_limits() -> LedgerLimits {
  { planning_work: 4, attempts: 2, holdings: 3, transfer_bytes: 10L,
    retained_bytes: 12L, execution_bytes: 20L, }
}

///|
fn backed_test_extent() -> BackedExecutionExtent {
  { offset: 0L, length: 48L, payload_offset: 8L, payload_length: 32L, }
}

///|
test "backed child charges shared bytes once and separate overhead to the original Ledger" {
  let (ledger, capacity, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = reserve_backed_execution_delegation(region, provider, child,
    backed_test_extent(), ExclusiveWrite, backed_test_limits(), 5L, 7L).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 87L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 5L)
  assert_eq(shared_allocation_usage(allocation).readers, 2)
  assert_eq(backed_execution_delegation_description(region, provider, child, ticket).unwrap(),
    (backed_test_extent(), ExclusiveWrite, backed_test_limits()))
  let usage = { ..ledger_usage(create_ledger(backed_test_limits()).unwrap()),
    planning_work: 2, attempts: 1, holdings: 2, transferred_bytes: 4L,
    held_bytes: 10L, reserved_retention_bytes: 2L,
    reserved_execution_bytes: 20L, peak_retention_bytes: 12L, }
  report_backed_execution_delegation(region, provider, child, ticket, usage).unwrap()
  report_backed_execution_delegation(region, provider, child, ticket, usage).unwrap()
  assert_eq(ledger_usage(ledger).planning_work, 2)
  assert_eq(ledger_usage(ledger).transferred_bytes, 4L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 87L)
  let final_usage = { ..usage, planning_work: 4, attempts: 2, holdings: 3,
    transferred_bytes: 8L, uncertain_transfer_bytes: 2L,
    held_bytes: 0L, reserved_retention_bytes: 0L, reserved_execution_bytes: 0L, }
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, Some(final_usage)).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 80L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).transferred_bytes, 8L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 2L)
  assert_eq(shared_allocation_usage(allocation).readers, 1)
  assert_true(close_backed_execution_region(region, provider).unwrap())
  release_shared_capacity(allocation).unwrap()
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "backed physical windows exclude writers while original read windows can share" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let limits = { ..backed_test_limits(), retained_bytes: 0L, execution_bytes: 8L, }
  let first = Ref(2)
  let second = Ref(3)
  let third = Ref(4)
  let read_extent = { ..backed_test_extent(), payload_length: 8L, }
  let a = reserve_backed_execution_delegation(region, provider, first, read_extent,
    ReadOnly, limits, 0L, 0L).unwrap()
  let b = reserve_backed_execution_delegation(region, provider, second, read_extent,
    ReadOnly, limits, 0L, 0L).unwrap()
  let before = ledger_usage(ledger)
  // Logical payload40..48 is disjoint from8..16, but physical24..48 overlaps.
  let crossing = { offset: 24L, length: 24L, payload_offset: 16L, payload_length: 8L, }
  assert_true(reserve_backed_execution_delegation(region, provider, third, crossing,
    ExclusiveWrite, limits, 0L, 0L) is Err(ExtentConflict))
  assert_eq(ledger_usage(ledger), before)
  let disjoint = { offset: 48L, length: 32L, payload_offset: 0L, payload_length: 32L, }
  let c = reserve_backed_execution_delegation(region, provider, third, disjoint,
    ExclusiveWrite, limits, 0L, 0L).unwrap()
  assert_eq(shared_allocation_usage(allocation).readers, 4)
  settle_backed_execution_after_owner_ack(region, provider, first, a, None).unwrap()
  settle_backed_execution_after_owner_ack(region, provider, second, b, None).unwrap()
  settle_backed_execution_after_owner_ack(region, provider, third, c, None).unwrap()
  assert_true(close_backed_execution_region(region, provider).unwrap())
}

///|
test "backed one-shot region and child reject foreign copied and duplicated originals" {
  let (ledger, capacity, allocation, provider, region) = backed_test_region()
  assert_true(issue_backed_execution_region(capacity, allocation, provider) is Err(CleanupPending))
  assert_true(borrow_shared_capacity(capacity, allocation) is Err(ClosedHolding))
  let child = Ref(2)
  let ticket = reserve_backed_execution_delegation(region, provider, child,
    backed_test_extent(), ExclusiveWrite, backed_test_limits(), 0L, 0L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(reserve_backed_execution_delegation(region, provider, child,
    backed_test_extent(), ExclusiveWrite, backed_test_limits(), 0L, 0L) is Err(DuplicateChild))
  assert_true(backed_execution_delegation_description(region, Ref(1), child, ticket) is Err(ForeignOriginal))
  assert_true(backed_execution_delegation_description(region, provider, Ref(2), ticket) is Err(ForeignOriginal))
  let copied : BackedExecutionDelegation[Ref[Int], Ref[Int]] = { ..ticket, }
  assert_true(backed_execution_delegation_description(region, provider, child, copied) is Err(ForeignOriginal))
  assert_eq(ledger_usage(ledger), before)
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_true(backed_execution_delegation_description(region, provider, child, ticket) is Err(ForeignOriginal))
  assert_true(close_backed_execution_region(region, provider).unwrap())
}

///|
test "backed extent validation is finite overflow-safe and failure-atomic" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  for extent in [
    { offset: -1L, length: 1L, payload_offset: 0L, payload_length: 1L, },
    { offset: 0L, length: 0L, payload_offset: 0L, payload_length: 1L, },
    { offset: 79L, length: 2L, payload_offset: 0L, payload_length: 1L, },
    { offset: 9223372036854775807L, length: 9223372036854775807L, payload_offset: 0L, payload_length: 1L, },
    { offset: 0L, length: 48L, payload_offset: 47L, payload_length: 2L, },
    { offset: 0L, length: 48L, payload_offset: 0L, payload_length: 31L, },
  ] {
    let before = ledger_usage(ledger)
    assert_true(reserve_backed_execution_delegation(region, provider, Ref(2), extent,
      ExclusiveWrite, backed_test_limits(), 0L, 0L) is Err(InvalidExtent))
    assert_eq(ledger_usage(ledger), before)
    assert_eq(shared_allocation_usage(allocation).readers, 1)
  }
  assert_true(close_backed_execution_region(region, provider).unwrap())
}

///|
test "backed report preserves byte bounds cumulative work and original peak" {
  let (ledger, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = reserve_backed_execution_delegation(region, provider, child,
    backed_test_extent(), ReadOnly, backed_test_limits(), 0L, 0L).unwrap()
  let usage = { ..ledger_usage(create_ledger(backed_test_limits()).unwrap()),
    planning_work: 2, attempts: 1, holdings: 1, transferred_bytes: 4L,
    held_bytes: 12L, peak_retention_bytes: 12L, }
  report_backed_execution_delegation(region, provider, child, ticket, usage).unwrap()
  for invalid in [
    { ..usage, held_bytes: 13L, peak_retention_bytes: 13L, },
    { ..usage, reserved_execution_bytes: 21L, },
    { ..usage, held_bytes: 0L, peak_retention_bytes: 0L, },
    { ..usage, planning_work: 1, },
    { ..usage, transferred_bytes: 3L, },
  ] {
    let before = ledger_usage(ledger)
    assert_true(report_backed_execution_delegation(region, provider, child, ticket, invalid)
      is Err(Resource(InvalidCharge)))
    assert_eq(ledger_usage(ledger), before)
  }
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, None).unwrap()
  assert_eq(ledger_usage(ledger).planning_work, 4)
  assert_eq(ledger_usage(ledger).transferred_bytes, 4L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 6L)
  assert_true(close_backed_execution_region(region, provider).unwrap())
}

///|
test "backed graceful closing rejects new children but retains entered cleanup and original borrow" {
  let (ledger, capacity, allocation, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = reserve_backed_execution_delegation(region, provider, child,
    backed_test_extent(), ExclusiveWrite, backed_test_limits(), 0L, 0L).unwrap()
  assert_false(close_backed_execution_region(region, provider).unwrap())
  close_shared_capacity(capacity).unwrap()
  let before = ledger_usage(ledger)
  assert_true(reserve_backed_execution_delegation(region, provider, Ref(3),
    backed_test_extent(), ReadOnly, backed_test_limits(), 0L, 0L) is Err(RegionClosing))
  assert_eq(ledger_usage(ledger), before)
  assert_true(release_shared_capacity(allocation) is Err(InvalidCharge))
  assert_true(settle_shared_capacity(capacity) is Err(InvalidCharge))
  let unused = ledger_usage(create_ledger(backed_test_limits()).unwrap())
  report_backed_execution_delegation(region, provider, child, ticket, unused).unwrap()
  settle_backed_execution_after_owner_ack(region, provider, child, ticket, Some(unused)).unwrap()
  assert_true(ticket.owner is None && ticket.child is None && ticket.borrow is None && ticket.logical is None)
  assert_eq(shared_allocation_usage(allocation).readers, 1)
  assert_true(close_backed_execution_region(region, provider).unwrap())
  assert_true(region.provider is None && region.capacity is None && region.allocation is None && region.owner_borrow is None)
  release_shared_capacity(allocation).unwrap()
  settle_shared_capacity(capacity).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "backed independent overhead shortage preserves the same region before child provisioning" {
  let (ledger, _, allocation, provider, region) = backed_test_region()
  let before = ledger_usage(ledger)
  assert_true(reserve_backed_execution_delegation(region, provider, Ref(2), backed_test_extent(),
    ExclusiveWrite, backed_test_limits(), 0L, 21L) is Err(Resource(ExecutionLimit)))
  assert_eq(ledger_usage(ledger), before)
  assert_true(region.children.is_empty())
  assert_eq(shared_allocation_usage(allocation).readers, 1)
  assert_true(close_backed_execution_region(region, provider).unwrap())
}
