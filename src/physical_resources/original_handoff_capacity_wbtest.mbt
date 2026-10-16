///|
fn handed_off_capacity_fixture() -> (
  Ledger,
  OriginalReadTestOrigin,
  FundedReadConsumer[OriginalReadTestOrigin],
) {
  let ledger = read_capacity_fixture(20L, 12L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  handoff_funded_read_consumer_capacity(consumer, origin, 1L, 1L).unwrap()
  |> ignore
  (ledger, origin, consumer)
}

///|
test "original handed-off covers exact capacity after work without another allocation" {
  let (ledger, origin, consumer) = handed_off_capacity_fixture()
  charge_planning(ledger, 1).unwrap()
  let before = ledger_usage(ledger)
  let quantity = quantity_usage(ledger)
  let serial = ledger.next_capacity_serial
  for _ in 0..<3 {
    assert_true(
      funded_read_consumer_handed_off_capacity_covers(consumer, origin, 7L, 5L),
    )
  }
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(consumer, origin, 8L, 5L),
  )
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(consumer, origin, 7L, 6L),
  )
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(consumer, origin, -1L, 5L),
  )
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(
      consumer,
      original_read_test_origin(),
      7L,
      5L,
    ),
  )
  let copied = { ..consumer, }
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(copied, origin, 7L, 5L),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(quantity_usage(ledger), quantity)
  assert_eq(ledger.next_capacity_serial, serial)
}

///|
test "original handed-off covers refuses park and stopping without returning capacity" {
  let (ledger, origin, consumer) = handed_off_capacity_fixture()
  let before = ledger_usage(ledger)
  let park = park_original_resource_consumer(consumer, origin).unwrap()
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(consumer, origin, 7L, 5L),
  )
  assert_true(original_resource_park_read_capacity_covers(park, origin, 7L, 5L))
  assert_eq(ledger_usage(ledger), before)
  let (stopping, other, stopped) = handed_off_capacity_fixture()
  let usage = ledger_usage(stopping)
  stop_funded_read_consumer(stopped).unwrap()
  assert_false(
    funded_read_consumer_handed_off_capacity_covers(stopped, other, 7L, 5L),
  )
  assert_true(
    settle_funded_read_consumer(stopped, false) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(stopping), usage)
}
