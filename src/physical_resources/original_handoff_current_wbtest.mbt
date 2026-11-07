///|
test "handed off consumer observes original origin without restoring initial usage" {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  let (same, capacity) = handoff_funded_read_consumer_capacity(
    consumer, origin, 10L, 5L,
  ).unwrap()
  assert_true(physical_equal(same, ledger))
  assert_true(
    funded_read_consumer_handed_off_origin(consumer) is Some(current) &&
    physical_equal(current, origin),
  )
  let forged : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: Some(claim),
  }
  assert_true(funded_read_consumer_handed_off_origin(forged) is None)
  let before = ledger_usage(ledger)
  charge_planning(ledger, 1).unwrap()
  assert_true(
    funded_read_consumer_handed_off_origin(consumer) is Some(current) &&
    physical_equal(current, origin),
  )
  assert_eq(ledger_usage(ledger).planning_work, before.planning_work + 1)
  assert_true(
    handoff_funded_read_consumer_capacity(consumer, origin, 1L, 1L)
    is Err(SpentClaim),
  )
  stop_funded_read_consumer(consumer).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  settle_capacity(ledger, capacity).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
}

///|
fn handed_off_output_fixture(
  quantities? : QuantityAmounts? = None,
) -> (Ledger, FundedReadConsumer[OriginalReadTestOrigin], Reservation) {
  let ledger = create_ledger({
    planning_work: 100,
    attempts: 3,
    holdings: 4,
    transfer_bytes: 20L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  if quantities is Some(_) {
    configure_quantities(ledger, {
      tokens: 10L,
      cost_units: 10L,
      duration_ms: 10L,
    }).unwrap()
  }
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 4, 0).unwrap()
  let producer = reserve_attempt(ledger, 9L, 10L, 12L, quantities~).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  handoff_funded_read_consumer_capacity(consumer, origin, 10L, 5L).unwrap()
  |> ignore
  (ledger, consumer, producer)
}

///|
test "handed off origin retains same completed output through independent scratch cleanup" {
  let (ledger, consumer, producer) = handed_off_output_fixture()
  let output = retain_allocation(ledger, producer, 4L).unwrap()
  settle_completed_output_reservation(ledger, producer, Some(output), 4L, 7L).unwrap()
  let pending = ledger_usage(ledger)
  assert_true(reservation_pending(producer))
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  assert_eq(ledger_usage(ledger), pending)
  assert_true(reservation_pending(producer))
  settle_execution_reservation(ledger, producer, remaining_execution=7L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  settle_reservation(ledger, producer).unwrap()
  assert_true(output.live)
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  release_allocation(ledger, output).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
}

///|
test "handed off origin refuses uncompleted changed producer and foreign output stamp" {
  let (ledger, consumer, producer) = handed_off_output_fixture()
  charge_transfer(ledger, producer, 1L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  let output = retain_allocation(ledger, producer, 4L).unwrap()
  settle_completed_output_reservation(ledger, producer, Some(output), 4L, 7L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  let completed = producer.completed_output
  producer.completed_output = Some((Some(output.serial + 1), 4L, 7L))
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  producer.completed_output = completed
  let forged : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: consumer.claim,
  }
  assert_true(funded_read_consumer_handed_off_origin(forged) is None)
  stop_funded_read_consumer(consumer).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
}

///|
test "handed off origin accepts completed empty output but not a changed bootstrap" {
  let (ledger, consumer, producer) = handed_off_output_fixture()
  settle_completed_output_reservation(ledger, producer, None, 0L, 0L).unwrap()
  assert_false(producer.open)
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  let bootstrap = consumer.claim.unwrap().descriptor.bootstrap
  mark_cleanup_pending(ledger, bootstrap.reservation).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
}

///|
test "handed off output recognition does not admit changed initial snapshot or bypass park" {
  let ledger = resource_park_test_ledger()
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 4, 0).unwrap()
  let producer = reserve_attempt(ledger, 9L, 10L, 12L).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let output = retain_allocation(ledger, producer, 4L).unwrap()
  settle_completed_output_reservation(ledger, producer, Some(output), 4L, 7L).unwrap()
  assert_true(
    fund_original_read(ledger, origin, descriptor, 7L, 5L)
    is Err(ChangedOriginalState),
  )
  let (same, consumer, producer) = handed_off_output_fixture()
  let output = retain_allocation(same, producer, 4L).unwrap()
  settle_completed_output_reservation(same, producer, Some(output), 4L, 7L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  let origin = consumer.claim.unwrap().descriptor.origin
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  let before = ledger_usage(same)
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  assert_true(original_resource_park_current(park, origin) is Some(_))
  assert_eq(ledger_usage(same), before)
  assert_true(reservation_pending(producer))
}

///|
test "handed off neutral quantity producer retains original completed output without readmission" {
  let (ledger, consumer, producer) = handed_off_output_fixture(
    quantities=Some(zero_quantities()),
  )
  // This is the same DATA selected by the installed Host for a non-Model task
  // on a Model-limited Ledger, not an absent quantity configuration.
  assert_eq(producer.quantities, quantity_neutral_amounts(ledger))
  let output = retain_allocation(ledger, producer, 4L).unwrap()
  settle_completed_output_reservation(ledger, producer, Some(output), 4L, 7L).unwrap()
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  assert_true(producer.quantities is None)
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(quantity_usage(ledger), quantities)
  settle_execution_reservation(ledger, producer, remaining_execution=7L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  assert_true(output.live)
  release_allocation(ledger, output).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
}

///|
test "handed off completed output refuses nonneutral and uncertain quantity preimages" {
  for
    amount in [
      { tokens: 1L, cost_units: 0L, duration_ms: 0L, },
      { tokens: 0L, cost_units: 1L, duration_ms: 0L, },
      { tokens: 0L, cost_units: 0L, duration_ms: 1L, },
    ] {
    let (ledger, consumer, producer) = handed_off_output_fixture(
      quantities=Some(amount),
    )
    let output = retain_allocation(ledger, producer, 4L).unwrap()
    settle_completed_output_reservation(ledger, producer, Some(output), 4L, 7L).unwrap()
    let before = quantity_usage(ledger)
    assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
    assert_eq(quantity_usage(ledger), before)
    assert_true(output.live)
  }
  let (ledger, consumer, producer) = handed_off_output_fixture(
    quantities=Some(zero_quantities()),
  )
  let output = retain_allocation(ledger, producer, 4L).unwrap()
  mark_quantities_uncertain(ledger, producer).unwrap()
  settle_completed_output_reservation(ledger, producer, Some(output), 4L, 7L).unwrap()
  let before = quantity_usage(ledger)
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  assert_eq(quantity_usage(ledger), before)
}
