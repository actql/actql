///|
// Actual Resource owner and tokens; finite explicit component limits do not
// certify an installed Model recipe or physical provider cleanup.
fn original_read_group_unclaimed_fixture() -> (
  Ledger,
  OriginalLedgerIdentity,
  FundedReadClaim[OriginalReadTestOrigin],
  Array[OriginalReadTestOrigin],
) {
  let ledger = read_capacity_fixture(100L, 100L)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 8, 0, 0).unwrap()
  let origins = [
    original_read_test_origin(),
    { run: "other-planned-model", host: "original-host", },
  ]
  let descriptor = issue_recorded_original_ledger_descriptor(
    identity,
    origins[0],
  ).unwrap()
  let claim = fund_original_read(ledger, origins[0], descriptor, 14L, 10L).unwrap()
  (ledger, identity, claim, origins)
}

///|
fn original_read_group_fixture() -> (
  Ledger,
  OriginalLedgerIdentity,
  FundedReadClaim[OriginalReadTestOrigin],
  Array[OriginalReadTestOrigin],
  Array[FundedReadConsumer[OriginalReadTestOrigin]],
) {
  let (ledger, identity, claim, origins) = original_read_group_unclaimed_fixture()
  let children = claim_funded_read_preparations(
    claim,
    origins[0],
    origins,
    [7L, 7L],
    [5L, 5L],
  ).unwrap()
  (ledger, identity, claim, origins, children)
}

///|
test "two original Model children grow their retained input bodies on the same read before handoff" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  let token = claim.read
  let admitted = claim.admitted
  let serial = ledger.next_capacity_serial
  let quantities = quantity_usage(ledger)
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  grow_funded_read_consumer_capacity(children[0], origins[0], 10L, 8L).unwrap()
  assert_true(physical_equal(token, claim.read))
  assert_eq(claim.read.reservation.retention, 17L)
  assert_eq(claim.read.reservation.execution, 13L)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(claim.admitted == admitted)
  assert_true(funded_read_consumer_available(children[1], origins[1], 7L, 5L))
  let (same, first) = handoff_funded_read_consumer_capacity(
    children[0],
    origins[0],
    10L,
    8L,
  ).unwrap()
  assert_true(physical_equal(same, ledger))
  charge_planning(ledger, 1).unwrap()
  enter_funded_read_consumer(children[1], origins[1], 7L, 5L).unwrap()
  grow_funded_read_consumer_capacity(children[1], origins[1], 12L, 9L).unwrap()
  assert_eq(claim.read.reservation.retention, 22L)
  assert_eq(claim.read.reservation.execution, 17L)
  assert_true(claim.admitted == admitted)
  assert_eq(ledger_usage(ledger).planning_work, 1)
  let (_, second) = handoff_funded_read_consumer_capacity(
    children[1],
    origins[1],
    12L,
    9L,
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[0], 11L, 9L)
    is Err(SpentClaim),
  )
  assert_eq(ledger_usage(ledger), before)
  settle_capacity(ledger, first).unwrap()
  settle_funded_read_consumer(children[0], true).unwrap()
  assert_true(capacity_reservation_open(token))
  settle_capacity(ledger, second).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origins[0], true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).planning_work, 1)
}

///|
// Explicit current/backing ports on the actual Resource owner, not physical
// VM/Host evidence. The normal installation supplies those original ports.
fn original_read_group_install_current(
  ledger : Ledger,
  current : (Int64) -> Int,
  window? : Ref[Int64]? = None,
  acquire? : ((Int64, Int64) -> Result[Unit, LedgerIssue])? = None,
) -> Unit {
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: window,
    acquire_window: acquire,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
}

///|
test "group Read grow refuses foreign unused shrink overflow and budget without changing peaks" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[0], 10L, 8L)
    is Err(SpentClaim),
  )
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let state = claim.read_state
  let serial = ledger.next_capacity_serial
  let quantities = quantity_usage(ledger)
  for
    (r, e) in [
      (101L, 8L),
      (10L, 101L),
      (6L, 5L),
      (7L, 4L),
      (9223372036854775807L, 8L),
    ] {
    assert_true(
      grow_funded_read_consumer_capacity(children[0], origins[0], r, e)
      is Err(Resource(_)),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_true(claim.read_state == state)
    assert_eq(
      original_read_child(claim, children[0]).unwrap().retained_bytes,
      7L,
    )
    assert_eq(
      original_read_child(claim, children[0]).unwrap().execution_bytes,
      5L,
    )
    assert_eq(ledger.next_capacity_serial, serial)
    assert_eq(quantity_usage(ledger), quantities)
  }
  let copy : FundedReadConsumer[OriginalReadTestOrigin] = {
    claim: Some(claim),
  }
  assert_true(
    grow_funded_read_consumer_capacity(copy, origins[0], 10L, 8L)
    is Err(SpentClaim),
  )
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[1], 10L, 8L)
    is Err(ForeignOrigin),
  )
  let calls = Ref(0)
  original_read_group_install_current(ledger, _ => {
    calls.val += 1
    0
  })
  grow_funded_read_consumer_capacity(children[0], origins[0], 10L, 8L).unwrap()
  assert_eq(calls.val, 1)
  settle_funded_read_consumer(children[0], true).unwrap()
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[0], 11L, 9L)
    is Err(SpentClaim),
  )
  assert_true(capacity_reservation_open(claim.read))
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origins[0], true).unwrap())
}

///|
test "group Read grow current reentry cannot hand off settle or allocate after original stop" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let state = claim.read_state
  let calls = Ref(0)
  let armed = Ref(true)
  let grow_refused = Ref(false)
  let handoff_refused = Ref(false)
  let settle_refused = Ref(false)
  let stop_pending = Ref(false)
  original_read_group_install_current(ledger, _ => {
    calls.val += 1
    if armed.val {
      armed.val = false
      grow_refused.val = grow_funded_read_consumer_capacity(
          children[0],
          origins[0],
          10L,
          8L,
        )
        is Err(CleanupPending)
      handoff_refused.val = handoff_funded_read_consumer_capacity(
          children[0],
          origins[0],
          1L,
          1L,
        )
        is Err(CleanupPending)
      settle_refused.val = settle_funded_read_consumer(children[0], true)
        is Err(CleanupPending)
      stop_pending.val = stop_funded_read_consumer(children[0])
        is Err(CleanupPending)
    }
    0
  })
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[0], 10L, 8L)
    is Err(CleanupPending),
  )
  assert_true(
    grow_refused.val &&
    handoff_refused.val &&
    settle_refused.val &&
    stop_pending.val,
  )
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger), before)
  assert_true(claim.read_state == state)
  assert_true(
    original_read_child(claim, children[0]).unwrap().phase == Stopping,
  )
  settle_funded_read_consumer(children[0], true).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origins[0], true).unwrap())
}

///|
test "group Read grow keeps an actual backing resize when its callback stops the same child" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let admitted = claim.admitted
  let serial = ledger.next_capacity_serial
  let window = Ref(29L) // Existing retention17 plus execution12.
  let acquired = Ref(0)
  original_read_group_install_current(
    ledger,
    _ => 0,
    window=Some(window),
    acquire=Some((r, e) => {
      acquired.val += 1
      guard stop_funded_read_consumer(children[0]) is Err(CleanupPending) else {
        return Err(ForeignOwner)
      }
      window.val = r + e
      Ok(())
    }),
  )
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[0], 10L, 8L)
    is Err(CleanupPending),
  )
  assert_eq(acquired.val, 1)
  assert_eq(claim.read.reservation.retention, 17L)
  assert_eq(claim.read.reservation.execution, 13L)
  assert_eq(
    ledger_usage(ledger).reserved_retention_bytes,
    before.reserved_retention_bytes + 3L,
  )
  assert_eq(
    ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes + 3L,
  )
  assert_true(
    claim.read_state == original_reservation_snapshot(claim.read.reservation),
  )
  assert_true(claim.admitted == admitted)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(
    original_read_child(claim, children[0]).unwrap().phase == Stopping,
  )
  assert_eq(
    original_read_child(claim, children[0]).unwrap().retained_bytes,
    10L,
  )
  let grown = ledger_usage(ledger)
  assert_true(
    settle_funded_read_consumer(children[0], false) is Err(CleanupPending),
  )
  assert_eq(ledger_usage(ledger), grown)
  settle_funded_read_consumer(children[0], true).unwrap()
  assert_true(capacity_reservation_open(claim.read))
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origins[0], true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "group Read grow retains acquired backing but refuses construction after original inventory closes" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  let window = Ref(29L)
  let acquired = Ref(0)
  original_read_group_install_current(
    ledger,
    _ => 0,
    window=Some(window),
    acquire=Some((r, e) => {
      acquired.val += 1
      guard finish_original_ledger_inventory(ledger, false) is Ok(false) else {
        return Err(ForeignOwner)
      }
      window.val = r + e
      Ok(())
    }),
  )
  assert_true(
    grow_funded_read_consumer_capacity(children[0], origins[0], 10L, 8L)
    is Err(CleanupPending),
  )
  assert_eq(acquired.val, 1)
  assert_eq(claim.read.reservation.retention, 17L)
  assert_eq(claim.read.reservation.execution, 13L)
  assert_true(
    claim.read_state == original_reservation_snapshot(claim.read.reservation),
  )
  assert_false(funded_read_consumer_available(children[0], origins[0], 10L, 8L))
  assert_false(funded_read_consumer_available(children[1], origins[1], 7L, 5L))
  settle_funded_read_consumer(children[0], true).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_funded_read_inventory(claim, origins[0], true).unwrap())
}

///|
test "closed original read group hands off two planned children on one claim and keeps pending cleanup" {
  let (ledger, identity, claim, origins, children) = original_read_group_fixture()
  let admitted = claim.admitted
  assert_true(
    claim_funded_read_preparation(claim, origins[0], 7L, 5L) is Err(SpentClaim),
  )
  assert_true(
    issue_recorded_original_ledger_descriptor(identity, origins[0])
    is Err(SpentClaim),
  )
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  let (first, a) = handoff_funded_read_consumer_capacity(
    children[0],
    origins[0],
    10L,
    5L,
  ).unwrap()
  assert_true(physical_equal(first, ledger))
  charge_planning(ledger, 1).unwrap()
  enter_funded_read_consumer(children[1], origins[1], 7L, 5L).unwrap()
  let (second, b) = handoff_funded_read_consumer_capacity(
    children[1],
    origins[1],
    11L,
    6L,
  ).unwrap()
  assert_true(physical_equal(second, ledger))
  assert_true(claim.admitted == admitted) // The first snapshot is never overwritten.
  assert_eq(ledger_usage(ledger).planning_work, 1)
  assert_true(
    enter_funded_read_consumer(children[0], origins[0], 7L, 5L)
    is Err(SpentClaim),
  )
  assert_true(
    handoff_funded_read_consumer_capacity(children[1], origins[1], 1L, 1L)
    is Err(SpentClaim),
  )
  settle_capacity(ledger, a).unwrap()
  stop_funded_read_consumer(children[0]).unwrap()
  settle_funded_read_consumer(children[0], true).unwrap()
  assert_true(capacity_reservation_open(claim.read))
  assert_true(
    settle_funded_read_consumer(children[1], false) is Err(CleanupPending),
  )
  assert_true(capacity_reservation_open(claim.read))
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  settle_capacity(ledger, b).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_false(capacity_reservation_open(claim.read))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 1)
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "closed original read group refuses duplicate foreign reordered and changed first input without a new claim" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  let foreign = original_read_test_origin()
  assert_false(funded_read_consumer_available(children[0], foreign, 7L, 5L))
  assert_true(
    enter_funded_read_consumer(children[0], foreign, 7L, 5L)
    is Err(ForeignOrigin),
  )
  assert_true(
    claim_funded_read_preparations(
      claim,
      origins[0],
      [origins[1], origins[0]],
      [7L, 7L],
      [5L, 5L],
    )
    is Err(SpentClaim),
  )
  let before = claim.admitted
  charge_planning(ledger, 1).unwrap()
  assert_true(
    enter_funded_read_consumer(children[0], origins[0], 7L, 5L)
    is Err(ChangedOriginalState),
  )
  assert_true(claim.admitted == before)
  assert_eq(ledger_usage(ledger).planning_work, 1)
  stop_funded_read_consumer(children[0]).unwrap()
  stop_funded_read_consumer(children[1]).unwrap()
  settle_funded_read_consumer(children[0], true).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "closed original read group current failure preserves the unused child and first original reservation" {
  let (ledger, _, claim, origins, children) = original_read_group_fixture()
  enter_funded_read_consumer(children[0], origins[0], 7L, 5L).unwrap()
  let (_, first) = handoff_funded_read_consumer_capacity(
    children[0],
    origins[0],
    10L,
    5L,
  ).unwrap()
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  let before = ledger_usage(ledger)
  assert_true(
    enter_funded_read_consumer(children[1], origins[1], 7L, 5L)
    is Err(ChangedOriginalState),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(capacity_reservation_open(first))
  assert_true(capacity_reservation_open(claim.read))
  settle_capacity(ledger, first).unwrap()
  stop_funded_read_consumer(children[0]).unwrap()
  stop_funded_read_consumer(children[1]).unwrap()
  settle_funded_read_consumer(children[0], true).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "closed original read first declaration refuses duplicate foreign order and excess partition before consumption" {
  let (ledger, _, claim, origins) = original_read_group_unclaimed_fixture()
  let before = ledger_usage(ledger)
  let foreign = original_read_test_origin()
  for
    selected in [
      [origins[0], origins[0]],
      [origins[1], origins[0]],
      [foreign, origins[1]],
    ] {
    assert_true(
      claim_funded_read_preparations(claim, origins[0], selected, [7L, 7L], [
        5L, 5L,
      ])
      is Err(ForeignOrigin),
    )
    assert_true(claim.children is None)
    assert_eq(ledger_usage(ledger), before)
  }
  assert_true(
    claim_funded_read_preparations(claim, origins[0], origins, [8L, 7L], [
      5L, 5L,
    ])
    is Err(Resource(RetentionLimit)),
  )
  assert_true(
    claim_funded_read_preparations(claim, origins[0], origins, [7L, 7L], [
      6L, 5L,
    ])
    is Err(Resource(ExecutionLimit)),
  )
  assert_eq(ledger_usage(ledger), before)
  let children = claim_funded_read_preparations(
    claim,
    origins[0],
    origins,
    [7L, 7L],
    [5L, 5L],
  ).unwrap()
  settle_funded_read_consumer(children[0], true).unwrap()
  settle_funded_read_consumer(children[1], true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
