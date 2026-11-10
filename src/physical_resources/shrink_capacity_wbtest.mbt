///|
test "byte-only shrink retains original live token and consumed history" {
  let ledger = read_capacity_fixture(20L, 20L)
  configure_quantities(ledger, {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }).unwrap()
  let send = reserve_attempt(
    ledger,
    11L,
    3L,
    0L,
    quantities=Some({ tokens: 13L, cost_units: 17L, duration_ms: 19L, }),
  ).unwrap()
  mark_transfer_uncertain(ledger, send, 11L).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let capacity = reserve_capacity(ledger, 7L, 5L).unwrap()
  let original = capacity.reservation
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  let serial = ledger.next_capacity_serial
  let attempts = ledger.next_attempt_serial
  shrink_capacity_reservation(ledger, capacity, 4L, 2L).unwrap()
  assert_eq(ledger_usage(ledger), {
    ..before,
    reserved_retention_bytes: before.reserved_retention_bytes - 3L,
    reserved_execution_bytes: before.reserved_execution_bytes - 3L,
  })
  assert_true(physical_equal(capacity.reservation, original))
  assert_true(capacity_reservation_matches(ledger, capacity, 4L, 2L))
  assert_eq(quantity_usage(ledger), quantities)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(ledger.next_attempt_serial, attempts)
  let shrunk = ledger_usage(ledger)
  shrink_capacity_reservation(ledger, capacity, 4L, 2L).unwrap()
  assert_eq(ledger_usage(ledger), shrunk)
  shrink_capacity_reservation(ledger, capacity, 0L, 0L).unwrap()
  assert_true(capacity_reservation_open(capacity))
  assert_eq(ledger_usage(ledger).live_reservations, before.live_reservations)
  settle_capacity(ledger, capacity).unwrap()
  settle_reservation(ledger, send).unwrap()
  assert_eq(quantity_usage(ledger), quantities)
}

///|
test "byte-only shrink refuses growth foreign negative and closed atomically" {
  let ledger = read_capacity_fixture(20L, 20L)
  let foreign = read_capacity_fixture(20L, 20L)
  let capacity = reserve_capacity(ledger, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  for (retained, execution) in [(8L, 4L), (6L, 6L), (-1L, 0L), (0L, -1L)] {
    assert_true(
      shrink_capacity_reservation(ledger, capacity, retained, execution)
      is Err(InvalidCharge),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_true(capacity_reservation_matches(ledger, capacity, 7L, 5L))
  }
  assert_true(
    shrink_capacity_reservation(foreign, capacity, 0L, 0L) is Err(ForeignOwner),
  )
  assert_eq(ledger_usage(ledger), before)
  settle_capacity(ledger, capacity).unwrap()
  let closed = ledger_usage(ledger)
  assert_true(
    shrink_capacity_reservation(ledger, capacity, 0L, 0L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), closed)
}

///|
test "byte-only shrink cannot adopt send or cleanup-pending custody" {
  let ledger = read_capacity_fixture(20L, 20L)
  let send = reserve_attempt(ledger, 0L, 7L, 5L).unwrap()
  let forged : CapacityReservation = { reservation: send, }
  let before = ledger_usage(ledger)
  assert_true(
    shrink_capacity_reservation(ledger, forged, 0L, 0L) is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), before)
  settle_reservation(ledger, send).unwrap()
  let capacity = reserve_capacity(ledger, 7L, 5L).unwrap()
  mark_cleanup_pending(ledger, capacity.reservation).unwrap()
  let pending = ledger_usage(ledger)
  assert_true(
    shrink_capacity_reservation(ledger, capacity, 0L, 0L) is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), pending)
}

///|
test "byte-only shrink checks post-callback bytes and never regrows a reentrant disposal" {
  let ledger = read_capacity_fixture(20L, 20L)
  let capacity = reserve_capacity(ledger, 7L, 5L).unwrap()
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      resize_capacity_reservation_current(ledger, capacity, 2L, 1L).unwrap()
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    shrink_capacity_reservation(ledger, capacity, 4L, 2L) is Err(InvalidCharge),
  )
  assert_eq(calls.val, 1)
  assert_true(capacity_reservation_matches(ledger, capacity, 2L, 1L))
}

///|
test "byte-only shrink preserves imported current and stopping cleanup boundaries" {
  let (frame, current, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(frame).unwrap()
  let (ledger, _, _) = take_imported_child_ledger(frame).unwrap()
  let capacity = reserve_capacity(ledger, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  current.val = -41
  assert_true(
    shrink_capacity_reservation(ledger, capacity, 4L, 2L)
    is Err(ChildFundingUnavailable),
  )
  assert_eq(ledger_usage(ledger), before)
  // A separate current original tests stopping; the unavailable one above
  // is never reset or rescued by replacing its callback observation.
  let (stopping, stop_current, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(stopping).unwrap()
  let (stopping_ledger, _, _) = take_imported_child_ledger(stopping).unwrap()
  let stopping_capacity = reserve_capacity(stopping_ledger, 7L, 5L).unwrap()
  stop_current.val = 1
  shrink_capacity_reservation(stopping_ledger, stopping_capacity, 4L, 2L).unwrap()
  assert_true(
    capacity_reservation_matches(stopping_ledger, stopping_capacity, 4L, 2L),
  )
  assert_true(
    reserve_capacity(stopping_ledger, 0L, 1L) is Err(ClosedReservation),
  )
}
