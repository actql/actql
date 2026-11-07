///|
// Same Resource originals only. Owner-after-acquisition calls stand in for
// physical receipts; these cases prove no Native mapping, allocator or ACK.
fn backed_window_fixture() -> (
  Ledger,
  SharedCapacity,
  SharedAllocation,
  BackedExecutionLiveProjection[Ref[Int], Ref[Int], Ref[Int]],
  Ref[Int],
  ImportedChildLedger,
  Ledger,
) raise {
  let parent = create_ledger({
    planning_work: 100,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 100L,
    retained_bytes: 64L,
    execution_bytes: 512L,
  }).unwrap()
  let capacity = reserve_shared_capacity(parent, 80L).unwrap()
  let control = allocate_shared_capacity(capacity, 16L).unwrap()
  let mapped = allocate_shared_capacity(capacity, 64L).unwrap()
  let provider = Ref(1)
  let region : BackedExecutionRegion[Ref[Int], Ref[Int]] = issue_backed_execution_region(
    capacity, mapped, provider,
  ).unwrap()
  let child = Ref(2)
  let policy = {
    ..backed_test_limits(),
    retained_bytes: 64L,
    execution_bytes: 128L,
  }
  let ticket = reserve_backed_execution_delegation(
    region,
    provider,
    child,
    { offset: 0L, length: 64L, payload_offset: 8L, payload_length: 56L, },
    ExclusiveWrite,
    policy,
    5L,
    7L,
    initial_window=Some(56L),
  ).unwrap()
  let read = borrow_backed_execution_read_use(region, provider, child, ticket).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read, runtime,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(frame).unwrap()
  let ledger = take_imported_original_child_ledger(frame).unwrap()
  assert_eq(ledger_limits(ledger), policy)
  (parent, capacity, control, projection, runtime, frame, ledger)
}

///|
test "backed child policy cannot grant bytes before same-parent acquired window publication" {
  let (parent, capacity, control, projection, runtime, frame, ledger) = backed_window_fixture()
  let read = reserve_capacity(ledger, 20L, 36L).unwrap()
  let before = ledger_usage(ledger)
  let parent_before = ledger_usage(parent)
  check_backed_original_child_window_demand(projection, runtime, 40L, 60L).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(parent), parent_before)
  assert_true(reserve_capacity(ledger, 1L, 0L) is Err(RetentionLimit))
  let growth = begin_shared_capacity_growth(capacity, control, 208L, 128L).unwrap()
  // Reserving parent backing is not acquisition or child permission.
  assert_true(reserve_capacity(ledger, 1L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  let parent_acquired = ledger_usage(parent)
  complete_backed_original_child_window_after_acquisition(
    projection, runtime, growth, 96L,
  ).unwrap()
  assert_eq(ledger_usage(parent), parent_acquired)
  assert_eq(ledger_usage(ledger), before)
  assert_eq(capacity.allocated, 208L)
  assert_eq(control.bytes, 144L)
  let ticket = projection.access.unwrap().ticket.unwrap()
  assert_eq(ticket.extent.length, 64L)
  assert_eq(ticket.extent.payload_length, 56L)
  assert_eq(ticket.current_window.unwrap().val, 152L)
  grow_execution_reservation_capacity(ledger, read.reservation, 40L, 60L).unwrap()
  assert_true(reserve_capacity(ledger, 24L, 29L) is Err(RetentionLimit))
  report_imported_child_ledger(frame).unwrap()
  assert_true(ticket.live_usage_reported)
  assert_true(
    complete_backed_original_child_window_after_acquisition(
      projection, runtime, growth, 96L,
    )
    is Err(Resource(ForeignOwner)),
  )
  settle_capacity(ledger, read).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(
    ledger_usage(parent).reserved_execution_bytes,
    parent_acquired.reserved_execution_bytes,
  )
}

///|
test "backed child rejects policy excess foreign runtime and unacquired usable suffix without changing its window" {
  let (parent, capacity, control, projection, runtime, _, ledger) = backed_window_fixture()
  let before = ledger_usage(parent)
  assert_eq(
    check_backed_original_child_window_demand(projection, runtime, 65L, 60L),
    Err(Resource(InvalidLimits)),
  )
  assert_true(
    check_backed_original_child_window_demand(projection, Ref(3), 40L, 60L)
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(parent), before)
  let growth = begin_shared_capacity_growth(capacity, control, 208L, 128L).unwrap()
  let pending = ledger_usage(parent)
  assert_eq(
    complete_backed_original_child_window_after_acquisition(
      projection, runtime, growth, 129L,
    ),
    Err(InvalidExtent),
  )
  assert_eq(
    complete_backed_original_child_window_after_acquisition(
      projection, runtime, growth, 0L,
    ),
    Err(InvalidExtent),
  )
  assert_true(
    capacity.growth is Some(original) && physical_equal(original, growth),
  )
  assert_eq(ledger_usage(parent), pending)
  assert_eq(
    projection.access.unwrap().ticket.unwrap().current_window.unwrap().val,
    56L,
  )
  assert_true(reserve_capacity(ledger, 57L, 0L) is Err(RetentionLimit))
  // Only the physical owner can select this atomic-failure/cleanup outcome.
  abort_shared_capacity_growth_after_cleanup(growth).unwrap()
  assert_eq(ledger_usage(parent), before)
}

///|
test "closing original child retains pending acquired growth without publishing another window" {
  let (parent, capacity, control, projection, runtime, _, ledger) = backed_window_fixture()
  let growth = begin_shared_capacity_growth(capacity, control, 208L, 128L).unwrap()
  let before = ledger_usage(parent)
  let access = projection.access.unwrap()
  stop_backed_execution_live_child(access, runtime).unwrap()
  assert_eq(
    complete_backed_original_child_window_after_acquisition(
      projection, runtime, growth, 96L,
    ),
    Err(RegionClosing),
  )
  assert_true(
    capacity.growth is Some(original) && physical_equal(original, growth),
  )
  assert_eq(access.ticket.unwrap().current_window.unwrap().val, 56L)
  assert_eq(ledger_usage(parent), before)
  assert_true(reserve_capacity(ledger, 1L, 0L) is Err(ClosedReservation))
}

///|
test "same physical owner publishes usable window before any projection or child Ledger exists" {
  let parent = create_ledger({
    planning_work: 100,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 100L,
    retained_bytes: 64L,
    execution_bytes: 512L,
  }).unwrap()
  let capacity = reserve_shared_capacity(parent, 80L).unwrap()
  let control = allocate_shared_capacity(capacity, 16L).unwrap()
  let mapped = allocate_shared_capacity(capacity, 64L).unwrap()
  let provider = Ref(1)
  let child = Ref(2)
  let region : BackedExecutionRegion[Ref[Int], Ref[Int]] = issue_backed_execution_region(
    capacity, mapped, provider,
  ).unwrap()
  let ticket = reserve_backed_execution_delegation(
    region,
    provider,
    child,
    { offset: 0L, length: 64L, payload_offset: 8L, payload_length: 56L, },
    ExclusiveWrite,
    { ..backed_test_limits(), retained_bytes: 64L, execution_bytes: 128L, },
    5L,
    7L,
    initial_window=Some(32L),
  ).unwrap()
  let growth = begin_shared_capacity_growth(capacity, control, 208L, 128L).unwrap()
  assert_true(ticket.read_use is None)
  complete_backed_execution_window_after_acquisition(
    region, provider, child, ticket, growth, 96L,
  ).unwrap()
  assert_eq(ticket.current_window.unwrap().val, 128L)
  assert_eq(ticket.extent.payload_length, 56L)
  let read = borrow_backed_execution_read_use(region, provider, child, ticket).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read, runtime,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(frame).unwrap()
  let ledger = take_imported_original_child_ledger(frame).unwrap()
  assert_true(
    physical_equal(
      frame.origin.current_window.unwrap(),
      ticket.current_window.unwrap(),
    ),
  )
  let held = reserve_capacity(ledger, 64L, 64L).unwrap()
  assert_true(reserve_capacity(ledger, 0L, 1L) is Err(RetentionLimit))
  settle_capacity(ledger, held).unwrap()
}

///|
test "acquired child window observation preserves usage and rejects foreign closing and retired originals" {
  let (parent, capacity, control, projection, runtime, _, ledger) = backed_window_fixture()
  let parent_before = ledger_usage(parent)
  let child_before = ledger_usage(ledger)
  assert_eq(
    read_backed_original_child_window_bytes(projection, runtime),
    Ok(56L),
  )
  assert_eq(
    read_backed_original_child_window_bytes(projection, Ref(3)),
    Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(parent), parent_before)
  assert_eq(ledger_usage(ledger), child_before)
  let growth = begin_shared_capacity_growth(capacity, control, 208L, 128L).unwrap()
  let pending = ledger_usage(parent)
  assert_eq(
    read_backed_original_child_window_bytes(projection, runtime),
    Ok(56L),
  )
  assert_eq(ledger_usage(parent), pending)
  complete_backed_original_child_window_after_acquisition(
    projection, runtime, growth, 96L,
  ).unwrap()
  assert_eq(
    read_backed_original_child_window_bytes(projection, runtime),
    Ok(152L),
  )
  assert_eq(ledger_usage(parent), pending)
  assert_eq(ledger_usage(ledger), child_before)
  let access = projection.access.unwrap()
  let ticket = access.ticket.unwrap()
  assert_eq(ticket.extent.payload_length, 56L)
  assert_eq(ticket.limits.retained_bytes, 64L)
  assert_eq(ticket.limits.execution_bytes, 128L)
  assert_eq(ticket.peak_retention, 0L)
  assert_false(ticket.live_usage_reported)
  stop_backed_execution_live_child(access, runtime).unwrap()
  assert_eq(
    read_backed_original_child_window_bytes(projection, runtime),
    Err(RegionClosing),
  )
  // Explicit Owner ACK port only; this component proves no physical cleanup.
  retire_backed_execution_live_child_after_owner_ack(access, runtime).unwrap()
  assert_eq(
    read_backed_original_child_window_bytes(projection, runtime),
    Err(Retired),
  )
  assert_eq(ledger_usage(parent), pending)
  assert_eq(ledger_usage(ledger), child_before)
}

///|
test "negative backed byte reports refuse before window subtraction without state or history mutation" {
  let (parent, _, _, projection, runtime, _, ledger) = backed_window_fixture()
  let before_parent = ledger_usage(parent)
  let before_child = ledger_usage(ledger)
  let ticket = projection.access.unwrap().ticket.unwrap()
  for value in [-1L, -9223372036854775808L] {
    for field in 0..<4 {
      let usage = {
        ..before_child,
        held_bytes: if field == 0 {
          value
        } else {
          0L
        },
        reserved_retention_bytes: if field == 1 {
          value
        } else {
          0L
        },
        reserved_execution_bytes: if field == 2 {
          value
        } else {
          0L
        },
        peak_retention_bytes: if field == 3 {
          value
        } else {
          0L
        },
      }
      assert_eq(
        report_backed_execution_live_child(projection, runtime, usage),
        Err(Resource(InvalidCharge)),
      )
      assert_eq(ledger_usage(parent), before_parent)
      assert_eq(ledger_usage(ledger), before_child)
      assert_eq(ticket.current_window.unwrap().val, 56L)
      assert_eq(ticket.peak_retention, 0L)
      assert_false(ticket.live_usage_reported)
    }
  }
}
