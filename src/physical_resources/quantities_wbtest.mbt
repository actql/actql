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
        assert_eq(ledger_usage(ledger).attempts, 0)
        assert_eq(ledger.next_attempt_serial, Some(1))
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

///|
test "shared two-Model duration covers four retained unknown attempts without refund" {
  let per_attempt : QuantityAmounts = {
    tokens: 33L,
    cost_units: 0L,
    duration_ms: 500L,
  }
  for (duration_ms, calls) in [(1000L, 2), (2000L, 4)] {
    let ledger = quantity_test_ledger()
    configure_quantities(ledger, { tokens: 66L, cost_units: 0L, duration_ms, }).unwrap()
    for _ in 0..<calls {
      let reservation = reserve_attempt(
        ledger,
        0L,
        0L,
        0L,
        quantities=Some(per_attempt),
      ).unwrap()
      mark_quantities_uncertain(ledger, reservation).unwrap()
      // The original response proves three tokens and no duration. Settling
      // the physical reservation cannot turn that unobserved time into zero.
      observe_quantities(ledger, reservation, tokens=Some(3L)).unwrap()
      settle_reservation(ledger, reservation).unwrap()
    }
    let before = quantity_usage(ledger)
    let physical = ledger_usage(ledger)
    assert_eq(before.consumed.tokens, calls.to_int64() * 3L)
    assert_eq(before.consumed.duration_ms, 0L)
    assert_eq(before.uncertain.duration_ms, duration_ms)
    assert_eq(before.reserved, zero_quantities())
    assert_true(
      reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(per_attempt))
      is Err(DurationLimit),
    )
    assert_eq(quantity_usage(ledger), before)
    assert_eq(ledger_usage(ledger), physical)
    assert_eq(physical.attempts, calls)
  }
}

///|
test "shared quantity configuration covers a component without granting or resetting its aggregate" {
  let ledger = quantity_test_ledger()
  let component : QuantityAmounts = {
    tokens: 66L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  assert_false(quantity_configuration_covers(ledger, Some(component)))
  let aggregate = { ..component, duration_ms: 2000L, }
  configure_quantities(ledger, aggregate).unwrap()
  assert_true(quantity_configuration_covers(ledger, Some(component)))
  assert_false(quantity_configuration_matches(ledger, Some(component)))
  assert_false(quantity_configuration_covers(ledger, None))
  assert_false(
    quantity_configuration_covers(ledger, Some({ ..component, tokens: -1L, })),
  )
  assert_false(
    quantity_configuration_covers(
      ledger,
      Some({ ..component, duration_ms: 2001L, }),
    ),
  )
  let attempt = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(component)).unwrap()
  mark_quantities_uncertain(ledger, attempt).unwrap()
  settle_reservation(ledger, attempt).unwrap()
  let before = quantity_usage(ledger)
  let physical = ledger_usage(ledger)
  assert_true(quantity_configuration_covers(ledger, Some(component)))
  assert_true(quantity_configuration_matches(ledger, Some(aggregate)))
  assert_eq(quantity_usage(ledger), before)
  assert_eq(ledger_usage(ledger), physical)
  assert_true(
    reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(component))
    is Err(TokenLimit),
  )
  assert_eq(quantity_usage(ledger), before)
}

///|
test "original quantity token observation preserves closed uncertain state without new current or allowance" {
  let ledger = quantity_test_ledger()
  let amount : QuantityAmounts = {
    tokens: 33L,
    cost_units: 0L,
    duration_ms: 500L,
  }
  configure_quantities(ledger, { ..amount, tokens: 66L, duration_ms: 1000L, }).unwrap()
  let token = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amount)).unwrap()
  assert_eq(
    reservation_quantity_state(ledger, token).unwrap(),
    (Some(amount), None, (false, false, false)),
  )
  assert_true(
    reservation_quantity_state(quantity_test_ledger(), token)
    is Err(ForeignOwner),
  )
  mark_quantities_uncertain(ledger, token).unwrap()
  observe_quantities(ledger, token, tokens=Some(3L)).unwrap()
  settle_reservation(ledger, token).unwrap()
  let before = quantity_usage(ledger)
  assert_eq(
    reservation_quantity_state(ledger, token).unwrap(),
    (None, Some({ ..amount, tokens: 0L, }), (true, false, false)),
  )
  assert_eq(quantity_usage(ledger), before)
}

///|
test "shared two-Model complete envelopes reserve the original four-call inventory atomically" {
  let amount : QuantityAmounts = {
    tokens: 33L,
    cost_units: 0L,
    duration_ms: 500L,
  }
  for (tokens, second_admitted) in [(66L, false), (132L, true)] {
    let ledger = quantity_test_ledger()
    configure_quantities(ledger, { tokens, cost_units: 0L, duration_ms: 2000L, }).unwrap()
    let first = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amount)).unwrap()
    let second = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amount)).unwrap()
    for token in [first, second] {
      mark_quantities_uncertain(ledger, token).unwrap()
      observe_quantities(ledger, token, tokens=Some(3L)).unwrap()
      settle_reservation(ledger, token).unwrap()
    }
    let third = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amount)).unwrap()
    let before = quantity_usage(ledger)
    let physical = ledger_usage(ledger)
    let fourth = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amount))
    if second_admitted {
      let fourth = fourth.unwrap()
      for token in [third, fourth] {
        mark_quantities_uncertain(ledger, token).unwrap()
        observe_quantities(ledger, token, tokens=Some(3L)).unwrap()
        settle_reservation(ledger, token).unwrap()
      }
      assert_eq(quantity_usage(ledger).consumed.tokens, 12L)
      assert_eq(quantity_usage(ledger).uncertain.duration_ms, 2000L)
      assert_true(
        reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amount))
        is Err(DurationLimit),
      )
    } else {
      assert_true(fourth is Err(TokenLimit))
      assert_eq(quantity_usage(ledger), before)
      assert_eq(ledger_usage(ledger), physical)
      settle_reservation(ledger, third).unwrap()
      assert_eq(quantity_usage(ledger).consumed.tokens, 6L)
    }
  }
}
