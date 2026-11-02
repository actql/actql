///|
test "execution remainder reduction preserves transfer quantities pending cleanup and spent history" {
  let ledger = create_ledger(test_limits()).unwrap()
  configure_quantities(ledger, {
    tokens: 11L,
    cost_units: 13L,
    duration_ms: 17L,
  }).unwrap()
  let reservation = reserve_attempt(
    ledger,
    9L,
    4L,
    15L,
    quantities=Some({ tokens: 3L, cost_units: 4L, duration_ms: 5L, }),
  ).unwrap()
  consume_reserved_attempt(ledger, reservation).unwrap()
  charge_transfer(ledger, reservation, 2L).unwrap()
  mark_transfer_uncertain(ledger, reservation, 2L).unwrap()
  let holding = retain_allocation(ledger, reservation, 2L).unwrap()
  mark_cleanup_pending(ledger, reservation).unwrap()
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  reduce_execution_reservation(ledger, reservation, 7L).unwrap()
  assert_eq(ledger_usage(ledger), { ..before, reserved_execution_bytes: 7L, })
  assert_eq(quantity_usage(ledger), quantities)
  assert_eq(reservation.transfer, 5L)
  assert_true(reservation_pending(reservation))
  assert_true(reservation_open(reservation))
  assert_eq(
    reservation_capacity_amounts(ledger, reservation).unwrap(),
    (2L, 7L),
  )
  let after = ledger_usage(ledger)
  reduce_execution_reservation(ledger, reservation, 7L).unwrap()
  assert_eq(ledger_usage(ledger), after)
  assert_true(
    reduce_execution_reservation(ledger, reservation, 8L) is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), after)
  reduce_execution_reservation(ledger, reservation, 0L).unwrap()
  assert_eq(ledger_usage(ledger), { ..after, reserved_execution_bytes: 0L, })
  assert_true(reservation_pending(reservation))
  assert_true(reservation_open(reservation))
  assert_eq(quantity_usage(ledger), quantities)
  settle_reservation(ledger, reservation).unwrap()
  release_allocation(ledger, holding).unwrap()
  assert_eq(ledger_usage(ledger).attempts, before.attempts)
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 2L)
}

///|
test "execution remainder reduction rejects foreign closed invalid and unavailable originals without credit" {
  let ledger = create_ledger(test_limits()).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 15L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    reduce_execution_reservation(foreign, reservation, 7L) is Err(ForeignOwner),
  )
  for amount in [-1L, 16L] {
    assert_true(
      reduce_execution_reservation(ledger, reservation, amount)
      is Err(InvalidCharge),
    )
    assert_eq(ledger_usage(ledger), before)
  }
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => -41,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    reduce_execution_reservation(ledger, reservation, 7L)
    is Err(ChildFundingUnavailable),
  )
  assert_eq(ledger_usage(ledger), before)
  ledger.imported_child = None
  settle_reservation(ledger, reservation).unwrap()
  let closed = ledger_usage(ledger)
  assert_true(
    reduce_execution_reservation(ledger, reservation, 0L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), closed)
}

///|
test "execution remainder reduction rechecks closure after the same original current callback" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 15L).unwrap()
  let armed = Ref(true)
  let calls = Ref(0)
  let closed : Ref[LedgerUsage?] = Ref(None)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      if armed.val {
        armed.val = false
        settle_reservation(ledger, reservation).unwrap()
        closed.val = Some(ledger_usage(ledger))
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    reduce_execution_reservation(ledger, reservation, 7L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), closed.val.unwrap())
  assert_eq(calls.val, 2)
}

///|
test "execution remainder reduction cannot return a running imported fixed Host allocation" {
  let ledger = create_ledger(test_limits()).unwrap()
  let capacity = imported_child_seed_capacity(ledger, -1, 15L)
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
    fixed_capacities: true,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let before = ledger_usage(ledger)
  assert_true(
    reduce_execution_reservation(ledger, capacity.reservation, 0L)
    is Err(ChildFundingUnavailable),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(calls.val, 1)
}
