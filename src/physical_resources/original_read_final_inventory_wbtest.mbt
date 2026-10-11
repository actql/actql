///|
test "funded original read final inventory keeps child and Run cleanup separate" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let foreign = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let read = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(read, origin, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    finish_funded_read_inventory(read, foreign, true) is Err(ForeignOrigin),
  )
  assert_true(
    finish_funded_read_inventory(read, origin, true) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(funded_read_consumer_origin(consumer) is Some(_))
  assert_false(ledger.original_inventory.unwrap().closing)
  assert_true(settle_funded_read(read, false) is Err(CleanupPending))
  assert_true(
    finish_funded_read_inventory(read, origin, true) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger), before)
  settle_funded_read(read, true).unwrap()
  assert_true(funded_read_consumer_origin(consumer) is None)
  assert_false(finish_funded_read_inventory(read, origin, false).unwrap())
  assert_true(capacity_reservation_open(bootstrap))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 2L)
  assert_true(finish_funded_read_inventory(read, origin, true).unwrap())
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_capacity_serial, Some(-3))
  assert_true(
    finish_funded_read_inventory(read, origin, true) is Err(SpentClaim),
  )
}

///|
test "funded original read final inventory retains zero-byte children and unknown usage" {
  let ledger = read_capacity_fixture(10L, 7L)
  let amounts : QuantityAmounts = {
    tokens: 3L,
    cost_units: 5L,
    duration_ms: 7L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 1, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let read = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  assert_true(
    physical_equal(handoff_funded_read(read, origin).unwrap(), ledger),
  )
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  let holding = retain_allocation(ledger, send, 0L).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let unknown = quantity_usage(ledger)
  assert_eq(unknown.uncertain, amounts)
  settle_funded_read(read, true).unwrap()
  assert_false(finish_funded_read_inventory(read, origin, true).unwrap())
  assert_true(capacity_reservation_open(bootstrap))
  assert_true(reservation_open(send))
  assert_true(holding.live)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(quantity_usage(ledger), unknown)
  settle_reservation(ledger, send).unwrap()
  assert_false(finish_funded_read_inventory(read, origin, true).unwrap())
  assert_true(capacity_reservation_open(bootstrap))
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  assert_eq(quantity_usage(ledger), unknown)
  release_allocation(ledger, holding).unwrap()
  assert_true(finish_funded_read_inventory(read, origin, true).unwrap())
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(quantity_usage(ledger), unknown)
  assert_eq(ledger.next_capacity_serial, Some(-3))
}
