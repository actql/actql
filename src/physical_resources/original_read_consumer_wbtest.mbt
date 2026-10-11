///|
test "original early consumer rejects duplicate allocation and preserves handoff custody" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let quantities = quantity_usage(ledger)
  // Synthetic exact envelope: this is not a physical layout coefficient.
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  assert_true(
    consumer.claim is Some(original) && physical_equal(original, claim),
  )
  assert_true(
    claim.phase is Preparing(current) && physical_equal(current, consumer),
  )
  assert_true(
    funded_read_consumer_origin(consumer) is Some(bound) &&
    physical_equal(bound, origin),
  )
  assert_true(funded_read_consumer_available(consumer, origin, 7L, 5L))
  let forged : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: Some(claim),
  }
  assert_false(funded_read_consumer_available(forged, origin, 7L, 5L))
  assert_true(funded_read_consumer_origin(forged) is None)
  stop_funded_read_consumer(forged)
  assert_true(settle_funded_read_consumer(forged, true) is Err(SpentClaim))
  assert_true(funded_read_consumer_available(consumer, origin, 7L, 5L))
  assert_true(
    handoff_funded_read_consumer_capacity(forged, origin, 1L, 1L)
    is Err(SpentClaim),
  )
  assert_true(
    claim_funded_read_preparation(claim, origin, 7L, 5L) is Err(SpentClaim),
  )
  assert_false(funded_read_available(claim, origin))
  assert_true(
    handoff_funded_read_capacity(claim, origin, 10L, 5L) is Err(SpentClaim),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(
    handoff_funded_read_consumer_capacity(consumer, origin, 1L, 1L)
    is Err(SpentClaim),
  )
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  assert_true(
    enter_funded_read_consumer(consumer, origin, 7L, 5L) is Err(SpentClaim),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  let (same, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 10L, 5L,
  ).unwrap()
  assert_true(physical_equal(same, ledger))
  assert_true(capacity_reservation_matches(same, capacity, 10L, 5L))
  assert_false(funded_read_consumer_available(consumer, origin, 7L, 5L))
  assert_true(funded_read_consumer_origin(consumer) is None)
  assert_true(
    handoff_funded_read_consumer_capacity(consumer, origin, 0L, 0L)
    is Err(SpentClaim),
  )
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_true(consumer.claim is Some(_))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 20L)
  settle_funded_read(claim, true).unwrap()
  assert_true(consumer.claim is None)
  assert_true(claim.phase is Reclaimed)
  assert_true(capacity_reservation_open(capacity))
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  settle_capacity(same, capacity).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original early consumer preserves uncertain quantities and spent capacity serials" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let amounts : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(quantity_usage(ledger).uncertain, amounts)
  let (same, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 10L, 5L,
  ).unwrap()
  assert_true(physical_equal(same, ledger))
  assert_eq(quantity_usage(same).uncertain, amounts)
  assert_true(settle_capacity(same, spent) is Err(ClosedReservation))
  assert_true(
    settle_funded_read_consumer(consumer, false) is Err(CleanupPending),
  )
  assert_true(consumer.claim is Some(_))
  assert_eq(ledger_usage(same).reserved_retention_bytes, 20L)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(consumer.claim is None)
  assert_true(capacity_reservation_open(capacity))
  settle_capacity(same, capacity).unwrap()
  assert_false(finish_original_ledger_inventory(same, true).unwrap())
  settle_reservation(same, send).unwrap()
  assert_true(finish_original_ledger_inventory(same, true).unwrap())
  assert_eq(quantity_usage(same).uncertain, amounts)
}

///|
test "original early consumer one short foreign and changed state do not spend admission" {
  let ledger = read_capacity_fixture(19L, 11L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_true(claim_funded_read_preparation(claim, origin, 8L, 5L) is Err(_))
  assert_true(claim_funded_read_preparation(claim, origin, 7L, 6L) is Err(_))
  assert_true(
    claim_funded_read_preparation(claim, origin, 0L, 5L)
    is Err(Resource(InvalidCharge)),
  )
  assert_true(
    claim_funded_read_preparation(claim, original_read_test_origin(), 7L, 5L)
    is Err(ForeignOrigin),
  )
  assert_true(funded_read_available(claim, origin))
  ledger.next_capacity_serial = None
  assert_true(
    claim_funded_read_preparation(claim, origin, 7L, 5L)
    is Err(ChangedOriginalState),
  )
  ledger.next_capacity_serial = serial
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  assert_true(
    enter_funded_read_consumer(consumer, original_read_test_origin(), 7L, 5L)
    is Err(ForeignOrigin),
  )
  assert_true(enter_funded_read_consumer(consumer, origin, 8L, 5L) is Err(_))
  assert_true(enter_funded_read_consumer(consumer, origin, 7L, 6L) is Err(_))
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  assert_true(
    handoff_funded_read_consumer_capacity(consumer, origin, 10L, 5L)
    is Err(Resource(_)),
  )
  assert_true(funded_read_consumer_available(consumer, origin, 7L, 5L))
  assert_false(
    funded_read_consumer_available(
      consumer,
      original_read_test_origin(),
      7L,
      5L,
    ),
  )
  assert_false(funded_read_consumer_available(consumer, origin, 8L, 5L))
  assert_false(funded_read_consumer_available(consumer, origin, 7L, 6L))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  let (same, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 1L, 1L,
  ).unwrap()
  settle_capacity(same, capacity).unwrap()
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original early consumer stopped pending and reclaimed cannot be borrowed again" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  stop_funded_read(claim)
  assert_true(funded_read_consumer_origin(consumer) is None)
  assert_false(funded_read_consumer_available(consumer, origin, 7L, 5L))
  assert_true(
    handoff_funded_read_consumer_capacity(consumer, origin, 1L, 1L)
    is Err(SpentClaim),
  )
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_true(
    consumer.claim is Some(original) && physical_equal(original, claim),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  settle_funded_read(claim, true).unwrap()
  assert_true(consumer.claim is None)
  assert_true(claim.phase is Reclaimed)
  assert_false(funded_read_consumer_available(consumer, origin, 7L, 5L))
  assert_true(
    claim_funded_read_preparation(claim, origin, 7L, 5L) is Err(SpentClaim),
  )
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
