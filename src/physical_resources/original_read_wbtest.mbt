///|
// The existing owner funds descriptor construction/authentication first. The
// explicit envelope must include controls, inventory, authentication workspace
// and overlapping read phases; positive bytes alone do not prove its adequacy.
// Public callers remain gated on independently reviewed profile derivation.
fn[T] issue_original_ledger_descriptor(
  ledger : Ledger,
  origin : T,
  bootstrap : CapacityReservation,
  reservations : Array[Reservation],
  holdings : Array[Holding],
  delegations : Array[ExecutionDelegation],
  max_items : Int,
) -> Result[OriginalLedgerDescriptor[T], OriginalReadIssue] {
  if max_items < 0 ||
    reservations.length() > max_items ||
    holdings.length() > max_items - reservations.length() ||
    delegations.length() > max_items - reservations.length() - holdings.length() {
    return Err(IncompleteInventory)
  }
  // Private white-box fixture entry only: preserve its explicit input order.
  // Production's recorded issuer borrows the existing slots directly and
  // allocates none of these fixture-only temporary collections.
  let selected_reservations = original_token_slots()
  for index, token in reservations {
    selected_reservations.push(token, index)
  }
  let selected_holdings = original_token_slots()
  for index, token in holdings {
    selected_holdings.push(token, index)
  }
  let selected_delegations = original_token_slots()
  for index, token in delegations {
    selected_delegations.push(token, index)
  }
  issue_original_ledger_descriptor_from_slots(
    ledger, origin, bootstrap, selected_reservations, selected_holdings, selected_delegations,
    max_items,
  )
}

///|
priv struct OriginalReadTestOrigin {
  mut run : String
  host : String
}

///|
fn original_read_test_origin() -> OriginalReadTestOrigin {
  let original = { run: "", host: "original-host", }
  original.run = "original-run"
  original
}

///|
test "funded original read exact fit includes bootstrap and hands off same ledger" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  assert_eq(origin.run, "original-run")
  assert_eq(origin.host, "original-host")
  // Identity tests need independently allocated equal-valued originals on
  // Native too; an immutable constant literal can be shared by the compiler.
  let another = original_read_test_origin()
  assert_eq(another.run, origin.run)
  assert_eq(another.host, origin.host)
  assert_false(physical_equal(another, origin))
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap()
  let duplicate = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  assert_true(
    issue_recorded_original_ledger_descriptor(identity, origin)
    is Err(SpentClaim),
  )
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
  assert_true(
    fund_original_read(ledger, origin, duplicate, 0L, 0L) is Err(SpentClaim),
  )
  settle_funded_read(claim, true).unwrap()
  assert_eq(ledger_usage(downstream).reserved_retention_bytes, 3L)
  assert_eq(ledger_usage(downstream).reserved_execution_bytes, 2L)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
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
    begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap()
    |> ignore
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
    assert_true(settle_capacity(ledger, bootstrap) is Err(InvalidCharge))
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  }
}

///|
test "funded original read refuses foreign run owner tampering and expired bootstrap" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let foreign = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap() |> ignore
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
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
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
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 3, 1, 1).unwrap() |> ignore
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
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  release_allocation(ledger, holding).unwrap()
  settle_reservation(ledger, send).unwrap()
  settle_execution_delegation(ledger, delegation, None).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
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
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 3, 0, 0).unwrap() |> ignore
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let spent = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, spent).unwrap()
  let descriptor = issue_original_ledger_descriptor(
    ledger,
    origin,
    bootstrap,
    [send],
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
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  settle_reservation(downstream, send).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(quantity_usage(downstream).uncertain, amounts)
}

///|
test "funded original read failure cancellation and pending cleanup retain exact custody" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap() |> ignore
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
  stop_funded_read(claim).unwrap()
  assert_true(!funded_read_available(claim, origin))
  assert_true(handoff_funded_read(claim, origin) is Err(SpentClaim))
  assert_true(settle_funded_read(claim, false) is Err(CleanupPending))
  assert_eq(ledger_usage(ledger), before)
  assert_true(capacity_reservation_open(claim.read))
  assert_true(capacity_reservation_open(bootstrap))
  assert_true(!finish_original_ledger_inventory(ledger, false).unwrap())
  settle_funded_read(claim, true).unwrap()
  assert_true(settle_funded_read(claim, true) is Err(SpentClaim))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "funded original read zero-byte custody cannot be omitted or released early" {
  let ledger = read_capacity_fixture(10L, 7L)
  let origin = original_read_test_origin()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 3, 1, 1).unwrap()
  let zero = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let held = retain_allocation(ledger, zero, 0L).unwrap()
  let delegated = reserve_execution_delegation(
    ledger,
    {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    },
    0L,
    0L,
  ).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  // Byte sums are unchanged when any zero-byte resource is omitted.
  assert_true(
    issue_original_ledger_descriptor(ledger, origin, bootstrap, [], [], [], 4)
    is Err(IncompleteInventory),
  )
  assert_true(
    issue_original_ledger_descriptor(
      ledger,
      origin,
      bootstrap,
      [zero, delegated.reservation],
      [],
      [delegated],
      4,
    )
    is Err(IncompleteInventory),
  )
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let claim = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  handoff_funded_read(claim, origin).unwrap() |> ignore
  settle_funded_read(claim, true).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 3L)
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(ClosedReservation))
  settle_reservation(ledger, zero).unwrap()
  settle_execution_delegation(ledger, delegated, None).unwrap()
  assert_true(!finish_original_ledger_inventory(ledger, true).unwrap())
  release_allocation(ledger, held).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "funded original read census rejects late setup and one-short token storage atomically" {
  let late = read_capacity_fixture(10L, 7L)
  let zero = reserve_attempt(late, 0L, 0L, 0L).unwrap()
  settle_reservation(late, zero).unwrap()
  let bootstrap = reserve_capacity(late, 3L, 2L).unwrap()
  assert_true(
    begin_original_ledger_inventory(late, bootstrap, 1, 0, 0)
    is Err(ChangedOriginalState),
  )
  settle_capacity(late, bootstrap).unwrap()
  let ledger = read_capacity_fixture(10L, 7L)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 0, 0, 0).unwrap()
  let before = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(RetentionLimit))
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  let descriptor = issue_recorded_original_ledger_descriptor(
    identity,
    original_read_test_origin(),
  ).unwrap()
  assert_eq(descriptor.reservations.length(), 0)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
