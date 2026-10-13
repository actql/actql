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
