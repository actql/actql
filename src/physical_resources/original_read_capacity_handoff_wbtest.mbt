///|
test "funded capacity handoff preserves original ledger and separate cleanup custody" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  assert_true(funded_read_preparation_available(claim, origin, 5L))
  assert_false(funded_read_preparation_available(claim, origin, 6L))
  assert_false(funded_read_preparation_available(claim, origin, -1L))
  // Synthetic exact charges isolate the pre-allocation guard, not a Node
  // layout coefficient. Aggregate headroom includes bootstrap but cannot
  // enlarge this exact original read token.
  let before_guard = ledger_usage(ledger)
  let serial_before_guard = ledger.next_capacity_serial
  assert_true(
    funded_read_preparation_available(claim, origin, 5L, retained_bytes=7L),
  )
  assert_false(
    funded_read_preparation_available(claim, origin, 5L, retained_bytes=8L),
  )
  assert_false(
    funded_read_preparation_available(claim, origin, 6L, retained_bytes=7L),
  )
  assert_false(
    funded_read_preparation_available(claim, origin, 5L, retained_bytes=-1L),
  )
  assert_eq(ledger_usage(ledger), before_guard)
  assert_eq(ledger.next_capacity_serial, serial_before_guard)
  assert_false(
    funded_read_preparation_available(claim, original_read_test_origin(), 5L),
  )
  let before_quantity = quantity_usage(ledger)
  let (same, capacity) = handoff_funded_read_capacity(claim, origin, 10L, 5L).unwrap()
  assert_false(
    funded_read_preparation_available(claim, origin, 5L, retained_bytes=7L),
  )
  assert_true(physical_equal(ledger, same))
  assert_eq(ledger_usage(same).reserved_retention_bytes, 20L)
  assert_eq(ledger_usage(same).reserved_execution_bytes, 12L)
  assert_eq(ledger_usage(same).attempts, 0)
  assert_eq(quantity_usage(same), before_quantity)
  assert_true(capacity_reservation_open(capacity))
  assert_true(capacity_reservation_matches(same, capacity, 10L, 5L))
  assert_false(capacity_reservation_matches(same, capacity, 9L, 5L))
  capacity.reservation.cleanup_pending = true
  assert_false(capacity_reservation_matches(same, capacity, 10L, 5L))
  capacity.reservation.cleanup_pending = false
  assert_false(
    capacity_reservation_matches(
      read_capacity_fixture(20L, 12L),
      capacity,
      10L,
      5L,
    ),
  )
  assert_true(
    handoff_funded_read_capacity(claim, origin, 0L, 0L) is Err(SpentClaim),
  )
  assert_true(handoff_funded_read(claim, origin) is Err(SpentClaim))
  // Finishing read custody cannot erase the independently retained Model token.
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_eq(ledger_usage(same).reserved_retention_bytes, 20L)
  settle_funded_read(claim, true).unwrap()
  assert_eq(ledger_usage(same).reserved_retention_bytes, 13L)
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(capacity_reservation_open(capacity))
  settle_capacity(same, capacity).unwrap()
  assert_false(capacity_reservation_matches(same, capacity, 10L, 5L))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(same).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(same).reserved_execution_bytes, 0L)
  assert_true(settle_capacity(same, capacity) is Err(ClosedReservation))
}

///|
test "funded capacity handoff one-short invalid and foreign retain a retryable claim" {
  for (retained, execution) in [(19L, 12L), (20L, 11L)] {
    let ledger = read_capacity_fixture(retained, execution)
    let origin = original_read_test_origin()
    let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
    let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
    let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
    let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
    let before = ledger_usage(ledger)
    let serial = ledger.next_capacity_serial
    assert_true(
      handoff_funded_read_capacity(claim, origin, 10L, 5L) is Err(Resource(_)),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, serial)
    assert_true(funded_read_available(claim, origin))
    assert_true(
      handoff_funded_read_capacity(claim, original_read_test_origin(), 1L, 1L)
      is Err(ForeignOrigin),
    )
    assert_true(
      handoff_funded_read_capacity(claim, origin, -1L, 1L)
      is Err(Resource(InvalidCharge)),
    )
    assert_eq(ledger_usage(ledger), before)
    let (same, token) = handoff_funded_read_capacity(claim, origin, 1L, 1L).unwrap()
    assert_true(physical_equal(same, ledger))
    settle_capacity(same, token).unwrap()
    settle_funded_read(claim, true).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  }
}

///|
test "funded capacity handoff rejects changed originals and stopping spent serial" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  ledger.next_capacity_serial = None
  assert_true(
    handoff_funded_read_capacity(claim, origin, 1L, 1L)
    is Err(ChangedOriginalState),
  )
  ledger.next_capacity_serial = Some(-3)
  assert_eq(ledger_usage(ledger), before)
  assert_true(funded_read_available(claim, origin))
  stop_funded_read(claim).unwrap()
  assert_false(
    funded_read_preparation_available(claim, origin, 5L, retained_bytes=7L),
  )
  assert_false(funded_read_preparation_available(claim, origin, 1L))
  assert_true(
    handoff_funded_read_capacity(claim, origin, 1L, 1L) is Err(SpentClaim),
  )
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "funded capacity handoff preserves original unknown quantities and spent tokens" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let amounts : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  assert_true(quantity_configuration_matches(ledger, Some(amounts)))
  assert_false(quantity_configuration_matches(ledger, None))
  assert_false(
    quantity_configuration_matches(ledger, Some({ ..amounts, tokens: 14L, })),
  )
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  assert_eq(ledger.next_capacity_serial, Some(-4))
  let (same, token) = handoff_funded_read_capacity(claim, origin, 10L, 5L).unwrap()
  assert_true(physical_equal(same, ledger))
  assert_eq(same.next_capacity_serial, Some(-5))
  assert_eq(quantity_usage(same).uncertain, amounts)
  assert_true(quantity_configuration_matches(same, Some(amounts)))
  assert_true(reservation_open(send))
  assert_true(settle_capacity(same, spent) is Err(ClosedReservation))
  assert_true(
    reserve_attempt(
      same,
      0L,
      0L,
      0L,
      quantities=Some({ ..zero_quantities(), tokens: 1L, }),
    )
    is Err(TokenLimit),
  )
  settle_capacity(same, token).unwrap()
  settle_funded_read(claim, true).unwrap()
  assert_false(finish_original_ledger_inventory(same, true).unwrap())
  settle_reservation(same, send).unwrap()
  assert_true(finish_original_ledger_inventory(same, true).unwrap())
  assert_eq(quantity_usage(same).uncertain, amounts)
}
