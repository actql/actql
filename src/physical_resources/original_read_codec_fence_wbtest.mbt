///|
test "original codec fence does not refresh admission after unrelated planning consumption" {
  for entered in [false, true] {
    let ledger = create_ledger({
      planning_work: 20,
      attempts: 2,
      holdings: 3,
      transfer_bytes: 11L,
      retained_bytes: 20L,
      execution_bytes: 12L,
    }).unwrap()
    let origin = original_read_test_origin()
    let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
    let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
    let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
    let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
    let admitted = claim.admitted
    let serial = ledger.next_capacity_serial
    let quantities = quantity_usage(ledger)
    let consumer = if entered {
      let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
      enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
      Some(consumer)
    } else {
      None
    }
    // The private writer has seventeen fixed encoding blocks. This test only
    // consumes real planning work; it grants no writer or snapshot-refresh API.
    charge_planning(ledger, 17).unwrap()
    let charged = ledger_usage(ledger)
    assert_eq(charged.planning_work, 17)
    assert_true(claim.admitted == admitted)
    assert_false(funded_read_available(claim, origin))
    match consumer {
      Some(consumer) => {
        assert_false(funded_read_consumer_available(consumer, origin, 7L, 5L))
        assert_true(
          handoff_funded_read_consumer_capacity(consumer, origin, 10L, 5L)
          is Err(ChangedOriginalState),
        )
        assert_true(
          consumer.claim is Some(original) && physical_equal(original, claim),
        )
      }
      None => {
        assert_true(
          claim_funded_read_preparation(claim, origin, 7L, 5L)
          is Err(ChangedOriginalState),
        )
        assert_true(
          handoff_funded_read_capacity(claim, origin, 10L, 5L)
          is Err(ChangedOriginalState),
        )
      }
    }
    assert_eq(ledger_usage(ledger), charged)
    assert_eq(ledger.next_capacity_serial, serial)
    assert_eq(quantity_usage(ledger), quantities)
    assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
    assert_eq(ledger_usage(ledger), charged)
    assert_true(capacity_reservation_open(claim.read))
    settle_funded_read(claim, true).unwrap()
    if consumer is Some(consumer) {
      assert_true(consumer.claim is None)
    }
    assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
    assert_eq(ledger_usage(ledger).planning_work, 17)
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
    assert_eq(ledger.next_capacity_serial, serial)
  }
}

///|
test "original codec fence rejects changed child snapshots with unchanged aggregate bytes" {
  let ledger = read_capacity_fixture(30L, 20L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let first = reserve_capacity(ledger, 2L, 1L).unwrap()
  let second = reserve_capacity(ledger, 4L, 2L).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  // White-box corruption, not a public mutation API: the same aggregate cannot
  // authenticate a different distribution across the original child tokens.
  first.reservation.retention = 3L
  second.reservation.retention = 3L
  assert_eq(first.reservation.retention + second.reservation.retention, 6L)
  assert_eq(ledger_usage(ledger), usage)
  assert_false(funded_read_consumer_available(consumer, origin, 7L, 5L))
  assert_true(
    handoff_funded_read_consumer_capacity(consumer, origin, 10L, 5L)
    is Err(ChangedOriginalState),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(
    settle_funded_read_consumer(consumer, false) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_true(
    consumer.claim is Some(original) && physical_equal(original, claim),
  )
  // Repair only the fault-injected fixture before its owning cleanup. Product
  // code must neither repair a snapshot nor reconstruct a child from totals.
  first.reservation.retention = 2L
  second.reservation.retention = 4L
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(consumer.claim is None)
  assert_false(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_true(capacity_reservation_open(first))
  assert_true(capacity_reservation_open(second))
  settle_capacity(ledger, first).unwrap()
  settle_capacity(ledger, second).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_capacity_serial, serial)
}

///|
test "original codec fence precharged work remains spent through same ledger handoff" {
  for planning in [16, 17] {
    let ledger = create_ledger({
      planning_work: planning,
      attempts: 2,
      holdings: 3,
      transfer_bytes: 11L,
      retained_bytes: 20L,
      execution_bytes: 12L,
    }).unwrap()
    let origin = original_read_test_origin()
    let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
    let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
    let before = ledger_usage(ledger)
    let serial = ledger.next_capacity_serial
    // Feasibility of existing Owner ordering only: this is not a codec permit
    // or a public prepayment API. No descriptor/read exists before this charge.
    if planning == 16 {
      assert_true(charge_planning(ledger, 17) is Err(PlanningLimit))
      assert_eq(ledger_usage(ledger), before)
      assert_eq(ledger.next_capacity_serial, serial)
      let inventory = ledger.original_inventory.unwrap()
      assert_false(inventory.descriptor_issued)
      assert_false(inventory.read_claimed)
      assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
      continue
    }
    charge_planning(ledger, 17).unwrap()
    let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
    let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
    assert_eq(claim.admitted.usage.planning_work, 17)
    let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
    enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
    let (same, capacity) = handoff_funded_read_consumer_capacity(
      consumer, origin, 10L, 5L,
    ).unwrap()
    assert_true(physical_equal(same, ledger))
    assert_eq(ledger_usage(same).planning_work, 17)
    assert_true(
      settle_funded_read_consumer(consumer, false) is Err(CleanupPending),
    )
    assert_eq(ledger_usage(same).reserved_retention_bytes, 20L)
    settle_funded_read_consumer(consumer, true).unwrap()
    assert_false(finish_funded_read_inventory(claim, origin, true).unwrap())
    settle_capacity(same, capacity).unwrap()
    assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
    assert_eq(ledger_usage(same).planning_work, 17)
    assert_eq(ledger_usage(same).reserved_retention_bytes, 0L)
    assert_eq(ledger_usage(same).reserved_execution_bytes, 0L)
  }
}
