///|
fn working_read_fixture(
  retained : Int64,
  execution : Int64,
  preparing? : Bool = false,
) -> (
  Ledger,
  OriginalReadTestOrigin,
  FundedReadClaim[OriginalReadTestOrigin],
  FundedReadConsumer[OriginalReadTestOrigin],
) {
  let ledger = read_capacity_fixture(retained, execution)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let consumer = claim_funded_read_preparation(claim, origin, 7L, 5L).unwrap()
  if !preparing {
    enter_funded_read_consumer(consumer, origin, 7L, 5L).unwrap()
  }
  (ledger, origin, claim, consumer)
}

///|
test "working Read grows the same original token without another slot or authority" {
  let (ledger, origin, claim, consumer) = working_read_fixture(40L, 30L)
  let token = claim.read
  let serial = ledger.next_capacity_serial
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  grow_funded_read_consumer_capacity(consumer, origin, 10L, 8L).unwrap()
  assert_true(physical_equal(token, claim.read))
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(quantity_usage(ledger), quantities)
  assert_eq(ledger_usage(ledger), {
    ..before,
    reserved_retention_bytes: before.reserved_retention_bytes + 3L,
    reserved_execution_bytes: before.reserved_execution_bytes + 3L,
    peak_retention_bytes: before.peak_retention_bytes + 3L,
  })
  assert_true(funded_read_consumer_available(consumer, origin, 10L, 8L))
  assert_true(
    funded_read_consumer_origin(consumer) is Some(original) &&
    physical_equal(original, origin),
  )
  let grown = ledger_usage(ledger)
  assert_true(
    grow_funded_read_consumer_capacity(consumer, origin, 9L, 8L)
    is Err(Resource(InvalidCharge)),
  )
  assert_eq(ledger_usage(ledger), grown)
  assert_true(
    settle_funded_read_consumer(consumer, false) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger), grown)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_capacity_serial, serial)
}

///|
test "working Read refusal preserves original snapshots and retryable capacity" {
  for (retained, execution) in [(10L, 5L), (7L, 9L)] {
    let (ledger, origin, claim, consumer) = working_read_fixture(12L, 10L)
    let before = ledger_usage(ledger)
    let admitted = claim.admitted
    let read_state = claim.read_state
    let serial = ledger.next_capacity_serial
    assert_true(
      grow_funded_read_consumer_capacity(consumer, origin, retained, execution)
      is Err(Resource(_)),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_true(claim.admitted == admitted)
    assert_true(claim.read_state == read_state)
    assert_eq(ledger.next_capacity_serial, serial)
    let foreign = original_read_test_origin()
    assert_true(
      grow_funded_read_consumer_capacity(consumer, foreign, 7L, 5L)
      is Err(ForeignOrigin),
    )
    let copy : FundedReadConsumer[OriginalReadTestOrigin] = {
      claim: Some(claim),
    }
    assert_true(
      grow_funded_read_consumer_capacity(copy, origin, 7L, 5L)
      is Err(SpentClaim),
    )
    grow_funded_read_consumer_capacity(consumer, origin, 8L, 6L).unwrap()
    settle_funded_read_consumer(consumer, true).unwrap()
    assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  }
}

///|
test "working Read never refreshes unrelated spent history" {
  let (ledger, origin, claim, consumer) = working_read_fixture(40L, 30L)
  let admitted = claim.admitted
  charge_planning(ledger, 1).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    grow_funded_read_consumer_capacity(consumer, origin, 10L, 8L)
    is Err(ChangedOriginalState),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(claim.admitted == admitted)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 1)
}

///|
fn working_read_reentry(preparing : Bool) -> Unit raise {
  let (ledger, origin, claim, consumer) = working_read_fixture(
    40L,
    30L,
    preparing~,
  )
  let grow = fn(retained : Int64, execution : Int64) {
    if preparing {
      grow_funded_read_preparing_capacity(consumer, origin, retained, execution)
    } else {
      grow_funded_read_consumer_capacity(consumer, origin, retained, execution)
    }
  }
  let before = ledger_usage(ledger)
  let calls = Ref(0)
  let nested_refused = Ref(false)
  let settle_refused = Ref(false)
  let stop_completed = Ref(false)
  let armed = Ref(true)
  // Explicit current port only: this fixture is not Native allocator proof.
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      if armed.val {
        armed.val = false
        nested_refused.val = grow(10L, 8L) is Err(SpentClaim)
        settle_refused.val = settle_funded_read_consumer(consumer, true)
          is Err(CleanupPending)
        stop_completed.val = stop_funded_read_consumer(consumer) is Ok(_)
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
  assert_true(grow(10L, 8L) is Err(CleanupPending))
  assert_true(nested_refused.val && settle_refused.val && stop_completed.val)
  // One outer current plus the distinct reentrant owning stop's current.
  assert_eq(calls.val, 2)
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    claim.phase is ConsumerStopping(original) &&
    physical_equal(original, consumer),
  )
  assert_true(capacity_reservation_open(claim.read))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
}

///|
test "working Read fences reentrant grow settle and original stop" {
  working_read_reentry(false)
}

///|
test "preparing Read fences the same current callback stop without entering or refunding" {
  working_read_reentry(true)
}

///|
test "working Read successful growth observes original current exactly once" {
  let (ledger, origin, claim, consumer) = working_read_fixture(40L, 30L)
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
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
  grow_funded_read_consumer_capacity(consumer, origin, 10L, 8L).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(claim.read.reservation.retention, 10L)
  assert_eq(claim.read.reservation.execution, 8L)
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
}

///|
test "working Read cleanup relocation copies stored state without refreshing admission" {
  let (ledger, origin, claim, consumer) = working_read_fixture(40L, 30L)
  assert_true(
    relocate_funded_read_consumer_cleanup_state(consumer, origin)
    is Err(CleanupPending),
  )
  grow_funded_read_consumer_capacity(consumer, origin, 10L, 8L).unwrap()
  let admitted = claim.admitted
  let read_state = claim.read_state
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  stop_funded_read_consumer(consumer).unwrap()
  let copy : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: Some(claim),
  }
  assert_true(
    relocate_funded_read_consumer_cleanup_state(copy, origin)
    is Err(CleanupPending),
  )
  assert_true(
    relocate_funded_read_consumer_cleanup_state(
      consumer,
      original_read_test_origin(),
    )
    is Err(ForeignOrigin),
  )
  // Unrelated later history must not be copied into the stored admission.
  charge_planning(ledger, 1).unwrap()
  relocate_funded_read_consumer_cleanup_state(consumer, origin).unwrap()
  assert_true(claim.admitted == admitted && claim.read_state == read_state)
  assert_false(physical_equal(claim.admitted, admitted))
  assert_false(physical_equal(claim.admitted.usage, admitted.usage))
  assert_false(physical_equal(claim.admitted.quantities, admitted.quantities))
  assert_false(
    physical_equal(
      claim.admitted.quantities.reserved,
      admitted.quantities.reserved,
    ),
  )
  assert_false(physical_equal(claim.read_state, read_state))
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(ledger_usage(ledger), {
    ..usage,
    planning_work: usage.planning_work + 1,
  })
  assert_false(funded_read_consumer_available(consumer, origin, 10L, 8L))
  assert_true(capacity_reservation_open(claim.read))
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_true(
    relocate_funded_read_consumer_cleanup_state(consumer, origin)
    is Err(SpentClaim),
  )
}

///|
test "preparing Read grows original capacity then enters exactly one consuming Execution" {
  let (ledger, origin, claim, consumer) = working_read_fixture(
    40L,
    30L,
    preparing=true,
  )
  let token = claim.read
  let serial = ledger.next_capacity_serial
  let before = ledger_usage(ledger)
  grow_funded_read_preparing_capacity(consumer, origin, 10L, 8L).unwrap()
  assert_true(physical_equal(token, claim.read))
  assert_true(
    claim.phase is Preparing(current) && physical_equal(current, consumer),
  )
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(ledger_usage(ledger).attempts, before.attempts)
  assert_eq(ledger_usage(ledger).transferred_bytes, before.transferred_bytes)
  assert_true(
    grow_funded_read_consumer_capacity(consumer, origin, 10L, 8L)
    is Err(SpentClaim),
  )
  assert_true(
    claim_funded_read_preparation(claim, origin, 10L, 8L) is Err(SpentClaim),
  )
  enter_funded_read_consumer(consumer, origin, 10L, 8L).unwrap()
  assert_true(
    enter_funded_read_consumer(consumer, origin, 10L, 8L) is Err(SpentClaim),
  )
  assert_true(
    grow_funded_read_preparing_capacity(consumer, origin, 11L, 9L)
    is Err(SpentClaim),
  )
  grow_funded_read_consumer_capacity(consumer, origin, 11L, 9L).unwrap()
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_capacity_serial, serial)
}

///|
test "preparing Read refusal preserves its original phase snapshots and cleanup" {
  let (ledger, origin, claim, consumer) = working_read_fixture(
    12L,
    10L,
    preparing=true,
  )
  let before = ledger_usage(ledger)
  let admitted = claim.admitted
  let read_state = claim.read_state
  assert_true(
    grow_funded_read_preparing_capacity(consumer, origin, 10L, 8L)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(physical_equal(claim.admitted, admitted))
  assert_true(physical_equal(claim.read_state, read_state))
  assert_true(
    claim.phase is Preparing(current) && physical_equal(current, consumer),
  )
  assert_true(
    grow_funded_read_preparing_capacity(
      consumer,
      original_read_test_origin(),
      8L,
      6L,
    )
    is Err(ForeignOrigin),
  )
  let copy : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: Some(claim),
  }
  assert_true(
    grow_funded_read_preparing_capacity(copy, origin, 8L, 6L) is Err(SpentClaim),
  )
  grow_funded_read_preparing_capacity(consumer, origin, 8L, 6L).unwrap()
  stop_funded_read_consumer(consumer).unwrap()
  assert_true(
    grow_funded_read_preparing_capacity(consumer, origin, 8L, 6L)
    is Err(SpentClaim),
  )
  assert_true(
    enter_funded_read_consumer(consumer, origin, 8L, 6L) is Err(SpentClaim),
  )
  settle_funded_read_consumer(consumer, true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origin, true).unwrap())
}
