///|
priv struct OriginalReadTestOrigin {
  run : String
  host : String
}

///|
fn original_read_test_origin() -> OriginalReadTestOrigin {
  { run: "original-run", host: "original-host", }
}

///|
test "funded original read exact fit includes bootstrap and hands off same ledger" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  assert_eq(origin.run, "original-run")
  assert_eq(origin.host, "original-host")
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let descriptor = issue_original_ledger_descriptor(
    ledger,
    origin,
    bootstrap,
    [],
    [],
    [],
    0,
  ).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  assert_true(funded_read_available(claim, origin))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 7L)
  assert_eq(ledger_usage(ledger).attempts, 0)
  let downstream = handoff_funded_read(claim, origin).unwrap()
  assert_true(physical_equal(downstream, ledger))
  assert_true(!funded_read_available(claim, origin))
  assert_true(handoff_funded_read(claim, origin) is Err(SpentClaim))
  assert_eq(ledger_usage(downstream).reserved_retention_bytes, 10L)
  settle_funded_read(claim, true).unwrap()
  assert_eq(ledger_usage(downstream).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(downstream).reserved_execution_bytes, 0L)
  assert_true(settle_funded_read(claim, true) is Err(SpentClaim))
}

///|
test "funded original read one short never grants read or refunds bootstrap" {
  for (retained, execution) in [(9L, 7L), (10L, 6L)] {
    let ledger = read_capacity_fixture(retained, execution)
    let origin = original_read_test_origin()
    let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
    let descriptor = issue_original_ledger_descriptor(
      ledger,
      origin,
      bootstrap,
      [],
      [],
      [],
      0,
    ).unwrap()
    let before = ledger_usage(ledger)
    let result = fund_original_read(ledger, origin, descriptor, 7L, 5L)
    assert_true(
      if retained == 9L {
        result is Err(Resource(RetentionLimit))
      } else {
        result is Err(Resource(ExecutionLimit))
      },
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, Some(-2))
    assert_true(!descriptor.claimed)
    assert_true(capacity_reservation_open(bootstrap))
    // The constructing owner still owns its bootstrap on failed admission.
    settle_capacity(ledger, bootstrap).unwrap()
  }
}

///|
test "funded original read refuses foreign run owner tampering and expired bootstrap" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let foreign = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let descriptor = issue_original_ledger_descriptor(
    ledger,
    origin,
    bootstrap,
    [],
    [],
    [],
    0,
  ).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    fund_original_read(ledger, foreign, descriptor, 7L, 5L)
    is Err(ForeignOrigin),
  )
  let other = read_capacity_fixture(10L, 7L)
  assert_true(
    fund_original_read(other, origin, descriptor, 7L, 5L)
    is Err(Resource(ForeignOwner)),
  )
  let tampered = {
    ..descriptor,
    state: { ..descriptor.state, next_capacity_serial: Some(-1), },
  }
  assert_true(
    fund_original_read(ledger, origin, tampered, 7L, 5L)
    is Err(ChangedOriginalState),
  )
  assert_eq(ledger_usage(ledger), before)
  settle_capacity(ledger, bootstrap).unwrap()
  assert_true(
    fund_original_read(ledger, origin, descriptor, 7L, 5L) is Err(SpentClaim),
  )
}

///|
test "funded original read requires actual reservation holding and delegation inventory" {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 5,
    holdings: 5,
    transfer_bytes: 11L,
    retained_bytes: 20L,
    execution_bytes: 10L,
  }).unwrap()
  let origin = original_read_test_origin()
  let send = reserve_attempt(ledger, 1L, 4L, 1L).unwrap()
  let holding = retain_allocation(ledger, send, 2L).unwrap()
  let delegation = reserve_execution_delegation(
    ledger,
    {
      planning_work: 1,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 2L,
      retained_bytes: 2L,
      execution_bytes: 1L,
    },
    2L,
    1L,
  ).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let tokens = [send, delegation.reservation]
  assert_true(
    issue_original_ledger_descriptor(
      ledger,
      origin,
      bootstrap,
      tokens,
      [],
      [delegation],
      4,
    )
    is Err(IncompleteInventory),
  )
  assert_true(
    issue_original_ledger_descriptor(
      ledger,
      origin,
      bootstrap,
      tokens,
      [holding],
      [],
      4,
    )
    is Err(IncompleteInventory),
  )
  assert_true(
    issue_original_ledger_descriptor(
      ledger,
      origin,
      bootstrap,
      [send, send],
      [holding],
      [delegation],
      4,
    )
    is Err(IncompleteInventory),
  )
  assert_true(
    issue_original_ledger_descriptor(
      ledger,
      origin,
      bootstrap,
      tokens,
      [holding],
      [delegation],
      3,
    )
    is Err(IncompleteInventory),
  )
  let descriptor = issue_original_ledger_descriptor(
    ledger,
    origin,
    bootstrap,
    tokens,
    [holding],
    [delegation],
    4,
  ).unwrap()
  // Mutating the caller's inventory cannot replace the descriptor's snapshots.
  tokens.clear()
  mark_cleanup_pending(ledger, send).unwrap()
  assert_true(
    fund_original_read(ledger, origin, descriptor, 1L, 1L)
    is Err(ChangedOriginalState),
  )
  assert_true(reservation_open(send))
  assert_true(holding.live)
}

///|
test "funded original read preserves spent serial and unknown quantity through cleanup" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let amounts : QuantityAmounts = {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }
  configure_quantities(ledger, amounts).unwrap()
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let descriptor = issue_original_ledger_descriptor(
    ledger,
    origin,
    bootstrap,
    [send, spent.reservation],
    [],
    [],
    2,
  ).unwrap()
  assert_eq(descriptor.state.next_capacity_serial, Some(-3))
  assert_eq(descriptor.state.quantities.uncertain, amounts)
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let downstream = handoff_funded_read(claim, origin).unwrap()
  assert_eq(downstream.next_capacity_serial, Some(-4))
  assert_true(
    reserve_attempt(
      downstream,
      0L,
      0L,
      0L,
      quantities=Some({ ..zero_quantities(), tokens: 1L, }),
    )
    is Err(TokenLimit),
  )
  settle_funded_read(claim, true).unwrap()
  assert_eq(quantity_usage(downstream).uncertain, amounts)
  assert_true(settle_capacity(downstream, spent) is Err(ClosedReservation))
  assert_true(reservation_open(send))
  settle_reservation(downstream, send).unwrap()
  assert_eq(quantity_usage(downstream).uncertain, amounts)
}

///|
test "funded original read failure cancellation and pending cleanup retain exact custody" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let descriptor = issue_original_ledger_descriptor(
    ledger,
    origin,
    bootstrap,
    [],
    [],
    [],
    0,
  ).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  stop_funded_read(claim)
  assert_true(!funded_read_available(claim, origin))
  assert_true(handoff_funded_read(claim, origin) is Err(SpentClaim))
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_eq(ledger_usage(ledger), before)
  assert_true(capacity_reservation_open(claim.read))
  assert_true(capacity_reservation_open(bootstrap))
  settle_funded_read(claim, true).unwrap()
  assert_true(settle_funded_read(claim, true) is Err(SpentClaim))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}
