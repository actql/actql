///|
fn quantity_test_ledger() -> Ledger {
  create_ledger({
    planning_work: 100,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
}

///|
test "quantity reservation is atomic at exact and one-short limits" {
  let exact : QuantityAmounts = {
    tokens: 33L,
    cost_units: 7L,
    duration_ms: 19L,
  }
  for
    (limits, expected) in [
      (exact, None),
      ({ ..exact, tokens: 32L, }, Some(TokenLimit)),
      ({ ..exact, cost_units: 6L, }, Some(CostLimit)),
      ({ ..exact, duration_ms: 18L, }, Some(DurationLimit)),
    ] {
    let ledger = quantity_test_ledger()
    configure_quantities(ledger, limits).unwrap()
    assert_true(reserve_attempt(ledger, 10L, 10L, 10L) is Err(InvalidCharge))
    let before = ledger_usage(ledger)
    let reserved = reserve_attempt(
      ledger,
      10L,
      10L,
      10L,
      quantities=Some(exact),
    )
    match expected {
      Some(issue) => {
        assert_true(reserved is Err(actual) && actual == issue)
        assert_eq(ledger_usage(ledger), before)
        assert_eq(quantity_usage(ledger).reserved, zero_quantities())
      }
      None => {
        let reservation = reserved.unwrap()
        assert_eq(quantity_usage(ledger).reserved, exact)
        assert_eq(configure_quantities(ledger, exact), Err(InvalidCharge))
        settle_reservation(ledger, reservation).unwrap()
        assert_eq(quantity_usage(ledger).reserved, zero_quantities())
        assert_eq(ledger_usage(ledger).attempts, 1)
        assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 0L)
      }
    }
  }
}

///|
test "unknown dispatched quantities survive failure cleanup without fake zero usage" {
  let amounts : QuantityAmounts = {
    tokens: 33L,
    cost_units: 7L,
    duration_ms: 19L,
  }
  let ledger = quantity_test_ledger()
  configure_quantities(ledger, amounts).unwrap()
  let dispatched = reserve_attempt(
    ledger,
    10L,
    10L,
    10L,
    quantities=Some(amounts),
  ).unwrap()
  let foreign = quantity_test_ledger()
  assert_eq(mark_quantities_uncertain(foreign, dispatched), Err(ForeignOwner))
  mark_quantities_uncertain(ledger, dispatched).unwrap()
  assert_eq(mark_quantities_uncertain(ledger, dispatched), Err(InvalidCharge))
  observe_quantities(ledger, dispatched).unwrap()
  settle_reservation(ledger, dispatched).unwrap()
  assert_eq(quantity_usage(ledger), {
    reserved: zero_quantities(),
    uncertain: amounts,
    consumed: zero_quantities(),
  })
  assert_true(
    reserve_attempt(
      ledger,
      0L,
      0L,
      0L,
      quantities=Some({ ..zero_quantities(), tokens: 1L, }),
    )
    is Err(TokenLimit),
  )
  assert_eq(
    observe_quantities(ledger, dispatched, tokens=Some(3L)),
    Err(ClosedReservation),
  )
}

///|
test "actual quantity observation releases excess while retaining unknown units" {
  let amounts : QuantityAmounts = {
    tokens: 33L,
    cost_units: 7L,
    duration_ms: 19L,
  }
  let ledger = quantity_test_ledger()
  configure_quantities(ledger, amounts).unwrap()
  let reservation = reserve_attempt(
    ledger,
    0L,
    0L,
    0L,
    quantities=Some(amounts),
  ).unwrap()
  mark_quantities_uncertain(ledger, reservation).unwrap()
  observe_quantities(ledger, reservation, tokens=Some(3L)).unwrap()
  assert_eq(quantity_usage(ledger).consumed.tokens, 3L)
  assert_eq(quantity_usage(ledger).uncertain, { ..amounts, tokens: 0L, })
  let before = quantity_usage(ledger)
  assert_eq(
    observe_quantities(ledger, reservation, tokens=Some(3L)),
    Err(InvalidCharge),
  )
  assert_eq(quantity_usage(ledger), before)
  observe_quantities(
    ledger,
    reservation,
    cost_units=Some(0L),
    duration_ms=Some(2L),
  ).unwrap()
  settle_reservation(ledger, reservation).unwrap()
  assert_eq(quantity_usage(ledger).uncertain, zero_quantities())
  assert_eq(quantity_usage(ledger).consumed, {
    tokens: 3L,
    cost_units: 0L,
    duration_ms: 2L,
  })
}

///|
test "a provider overrun remains charged and cannot overflow later admission" {
  let ledger = quantity_test_ledger()
  let amounts : QuantityAmounts = {
    tokens: 1L,
    cost_units: 0L,
    duration_ms: 0L,
  }
  configure_quantities(ledger, { ..amounts, tokens: 2L, }).unwrap()
  let first = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  let second = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, first).unwrap()
  assert_eq(
    observe_quantities(ledger, first, tokens=Some(9223372036854775807L)),
    Err(TokenLimit),
  )
  assert_eq(quantity_usage(ledger).consumed.tokens, 9223372036854775807L)
  assert_eq(quantity_usage(ledger).reserved.tokens, 1L)
  assert_true(
    reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(zero_quantities()))
    is Err(TokenLimit),
  )
  settle_reservation(ledger, first).unwrap()
  settle_reservation(ledger, second).unwrap()
  assert_eq(quantity_usage(ledger).consumed.tokens, 9223372036854775807L)
  assert_eq(quantity_usage(ledger).reserved.tokens, 0L)
}
