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

///|
// Reproduce the normal Model publication frontier with actual Resource
// owners. The original body stays nominally identical and borrowed while
// its existing publication entrance grows the same live reservation.
test "same adopted preparation publication growth retains its handed off Read origin" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 30000000L,
    execution_bytes: 30000000L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 4096L, 4096L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 5, 0, 0).unwrap()
  let input = [1]
  let body = [2]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    16760L,
    44776L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(owner, input, body, 16760L, 44776L).unwrap()
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let holder = borrow_preparation_body(owner).unwrap()
  let origin = original_read_test_origin()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let (_, child) = handoff_funded_read_consumer_capacity(
    consumer, origin, 10L, 10L,
  ).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  let original_token = owner.reservation.reservation
  reserve_preparation_publication_phase(holder, body, 9951112L, 9979192L).unwrap()
  assert_true(physical_equal(original_token, owner.reservation.reservation))
  assert_true(
    preparation_body_borrow_value(holder) is Some(current) &&
    physical_equal(current, body),
  )
  assert_true(capacity_reservation_open(owner.reservation))
  let same_origin = funded_read_consumer_handed_off_origin(consumer)
    .map(current => physical_equal(current, origin))
    .unwrap_or(false)
  // Keep the original stop/cleanup obligations even when the observation
  // above refuses. The final assertion cannot strand a live test owner.
  stop_funded_read_consumer(consumer).unwrap()
  settle_capacity(ledger, child).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_false(retire_preparation_capacity(owner).unwrap())
  assert_true(return_preparation_body_borrow(holder).unwrap())
  finish_original_ledger_inventory(ledger, true).unwrap() |> ignore
  assert_true(same_origin)
}

///|
fn handed_off_capacity_growth_fixture() -> (
  Ledger,
  FundedReadConsumer[OriginalReadTestOrigin],
  CapacityReservation,
  CapacityReservation,
) raise {
  let ledger = read_capacity_fixture(100L, 100L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 5, 0, 0).unwrap()
  let producer = reserve_capacity(ledger, 11L, 13L).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let (_, child) = handoff_funded_read_consumer_capacity(
    consumer, origin, 3L, 2L,
  ).unwrap()
  grow_capacity_reservation(ledger, producer, 21L, 23L).unwrap()
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  (ledger, consumer, producer, child)
}

///|
fn finish_handed_off_capacity_growth_fixture(
  ledger : Ledger,
  consumer : FundedReadConsumer[OriginalReadTestOrigin],
  producer : CapacityReservation,
  child : CapacityReservation,
) -> Unit {
  stop_funded_read_consumer(consumer).unwrap()
  settle_capacity(ledger, child).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  if capacity_reservation_open(producer) {
    settle_capacity(ledger, producer).unwrap()
  }
  finish_original_ledger_inventory(ledger, true).unwrap() |> ignore
}

///|
test "handed off capacity growth refuses changed charges and replacement tokens" {
  let (ledger, consumer, producer, child) = handed_off_capacity_growth_fixture()
  let token = producer.reservation
  let reject = fn() -> Unit raise {
    assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  }
  token.transfer = 1L
  reject()
  token.transfer = 0L
  token.quantities = Some(zero_quantities())
  reject()
  token.quantities = None
  token.uncertain_quantities = Some(zero_quantities())
  reject()
  token.uncertain_quantities = None
  token.attempt_reserved = true
  reject()
  token.attempt_reserved = false
  token.attempt_started = true
  reject()
  token.attempt_started = false
  token.cleanup_pending = true
  reject()
  token.cleanup_pending = false
  token.observed_quantities = (true, false, false)
  reject()
  token.observed_quantities = (false, false, false)
  token.completed_output = Some((None, 0L, 0L))
  reject()
  token.completed_output = None
  let descriptor = consumer.claim.unwrap().descriptor
  let pair = descriptor.reservations[0]
  // Equal serials and extents are only DATA. The existing inventory still
  // holds the actual original token, not either forged replacement below.
  let replacement = { ..token, }
  descriptor.reservations[0] = (replacement, pair.1)
  reject()
  let foreign = read_capacity_fixture(100L, 100L)
  descriptor.reservations[0] = ({ ..token, owner: foreign, }, pair.1)
  reject()
  descriptor.reservations[0] = pair
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  finish_handed_off_capacity_growth_fixture(ledger, consumer, producer, child)
}

///|
test "handed off capacity growth keeps shrink close quota and bootstrap fences" {
  for dimension in [0, 1] {
    let (ledger, consumer, producer, child) = handed_off_capacity_growth_fixture()
    let before = ledger_usage(ledger)
    assert_true(
      grow_capacity_reservation(ledger, producer, 1000L, 1000L) is Err(_),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
    resize_capacity_reservation(
      ledger,
      producer,
      if dimension == 0 {
        10L
      } else {
        21L
      },
      if dimension == 1 {
        12L
      } else {
        23L
      },
    ).unwrap()
    assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
    resize_capacity_reservation(ledger, producer, 21L, 23L).unwrap()
    assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
    let bootstrap = consumer.claim.unwrap().descriptor.bootstrap
    let bootstrap_before = original_reservation_snapshot(bootstrap.reservation)
    // This bootstrap belongs to its original inventory growth entrance;
    // generic capacity growth must not acquire that role.
    assert_true(grow_capacity_reservation(ledger, bootstrap, 4L, 3L) is Err(_))
    assert_true(
      original_reservation_snapshot(bootstrap.reservation) == bootstrap_before,
    )
    assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
    bootstrap.reservation.retention += 1L
    assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
    bootstrap.reservation.retention = bootstrap_before.retention
    assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
    settle_capacity(ledger, producer).unwrap()
    assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
    finish_handed_off_capacity_growth_fixture(ledger, consumer, producer, child)
  }
}

///|
test "handed off capacity growth never changes initial read admission" {
  let ledger = read_capacity_fixture(100L, 100L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let producer = reserve_capacity(ledger, 11L, 13L).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  grow_capacity_reservation(ledger, producer, 21L, 23L).unwrap()
  assert_true(funded_read_consumer_origin(consumer) is None)
  assert_true(
    enter_funded_read_consumer(consumer, origin, 7L, 5L)
    is Err(ChangedOriginalState),
  )
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  stop_funded_read_consumer(consumer).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  settle_capacity(ledger, producer).unwrap()
  finish_original_ledger_inventory(ledger, true).unwrap() |> ignore
}

///|
test "handed off capacity growth does not accept a regular attempt reservation" {
  let (ledger, consumer, producer) = handed_off_output_fixture()
  let original = original_reservation_snapshot(producer)
  resize_reservation_bytes_current(
    ledger,
    producer,
    producer.retention + 1L,
    producer.execution + 1L,
  ).unwrap()
  assert_true(producer.serial >= 0)
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  assert_true(
    original_capacity_growth_matches(ledger, producer, original) == false,
  )
}

///|
test "handed off capacity growth rechecks original identity after one reentrant current callback" {
  let (ledger, consumer, producer, child) = handed_off_capacity_growth_fixture()
  let inventory = ledger.original_inventory.unwrap()
  let token = producer.reservation
  let replacement = { ..token, }
  let calls = Ref(0)
  let replace = Ref(false)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      if replace.val {
        inventory.reservations.values[OriginalTokenSerial(token.serial)] = replacement
      }
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
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  assert_eq(calls.val, 1)
  replace.val = true
  assert_true(funded_read_consumer_handed_off_origin(consumer) is None)
  assert_eq(calls.val, 2)
  replace.val = false
  inventory.reservations.values[OriginalTokenSerial(token.serial)] = token
  assert_true(funded_read_consumer_handed_off_origin(consumer) is Some(_))
  assert_eq(calls.val, 3)
  finish_handed_off_capacity_growth_fixture(ledger, consumer, producer, child)
}
