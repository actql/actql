///|
test "neutral quantity DATA has no debit current callback or Model budget and shares immutable backing" {
  let first = quantity_test_ledger()
  assert_true(quantity_neutral_amounts(first) is None)
  let amounts : QuantityAmounts = {
    tokens: 1L,
    cost_units: 2L,
    duration_ms: 3L,
  }
  configure_quantities(first, amounts).unwrap()
  let second = quantity_test_ledger()
  configure_quantities(second, { ..amounts, tokens: 5L, }).unwrap()
  let calls = Ref(0)
  preparation_inventory_observe_current(first, Ref(None), calls)
  let before = ledger_usage(first)
  let zero = quantity_neutral_amounts(first)
  assert_true(zero is Some(value) && value == zero_quantities())
  assert_true(physical_equal(zero, quantity_neutral_amounts(second)))
  assert_eq(calls.val, 0)
  assert_eq(ledger_usage(first), before)
  assert_true(quantity_configuration_matches(first, Some(amounts)))
  assert_true(reserve_attempt(first, 0L, 0L, 0L) is Err(InvalidCharge))
  assert_eq(calls.val, 1)
  let child = reserve_attempt(first, 2L, 3L, 4L, quantities=zero).unwrap()
  assert_eq(calls.val, 2)
  assert_eq(ledger_usage(first).reserved_attempts, 1)
  assert_eq(ledger_usage(first).reserved_transfer_bytes, 2L)
  assert_eq(ledger_usage(first).reserved_retention_bytes, 3L)
  assert_eq(ledger_usage(first).reserved_execution_bytes, 4L)
  assert_eq(quantity_usage(first).reserved, zero_quantities())
  settle_reservation(first, child).unwrap()
}

///|
test "neutral quantities retain exact byte limits and refuse an existing Model quantity overrun" {
  let ledger = quantity_test_ledger()
  configure_quantities(ledger, { tokens: 1L, cost_units: 0L, duration_ms: 0L, }).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    reserve_attempt(
      ledger,
      101L,
      0L,
      0L,
      quantities=quantity_neutral_amounts(ledger),
    )
    is Err(TransferLimit),
  )
  assert_true(
    reserve_attempt(
      ledger,
      0L,
      101L,
      0L,
      quantities=quantity_neutral_amounts(ledger),
    )
    is Err(RetentionLimit),
  )
  assert_true(
    reserve_attempt(
      ledger,
      0L,
      0L,
      101L,
      quantities=quantity_neutral_amounts(ledger),
    )
    is Err(ExecutionLimit),
  )
  assert_eq(ledger_usage(ledger), before)
  let model = reserve_attempt(
    ledger,
    0L,
    0L,
    0L,
    quantities=Some({ tokens: 1L, cost_units: 0L, duration_ms: 0L, }),
  ).unwrap()
  mark_quantities_uncertain(ledger, model).unwrap()
  assert_eq(observe_quantities(ledger, model, tokens=Some(2L)), Err(TokenLimit))
  settle_reservation(ledger, model).unwrap()
  let spent = ledger_usage(ledger)
  assert_true(
    reserve_attempt(
      ledger,
      0L,
      0L,
      0L,
      quantities=quantity_neutral_amounts(ledger),
    )
    is Err(TokenLimit),
  )
  assert_eq(ledger_usage(ledger), spent)
  assert_eq(quantity_usage(ledger).consumed.tokens, 2L)
}

///|
test "original preparation input IO after quantity selection stays neutral and preserves input provenance" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  configure_quantities(ledger, { tokens: 3L, cost_units: 2L, duration_ms: 1L, }).unwrap()
  let before = quantity_usage(ledger)
  let child = begin_preparation_io(parent, input, 3L).unwrap()
  charge_preparation_io(child, 2L).unwrap()
  finish_preparation_io_after_cleanup(child).unwrap()
  assert_eq(quantity_usage(ledger), before)
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
}

///|
test "neutral projection cannot survive a changed original quantity configuration as an implicit waiver" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  let old = quantity_neutral_amounts(ledger)
  assert_true(old is None)
  let calls = Ref(0)
  let action = Ref(
    Some(() => configure_quantities(ledger, zero_quantities()).unwrap()),
  )
  preparation_inventory_observe_current(ledger, action, calls)
  let before = ledger_usage(ledger)
  assert_true(
    reserve_attempt(ledger, 0L, 0L, 0L, quantities=old) is Err(InvalidCharge),
  )
  assert_eq(calls.val, 2)
  assert_eq(ledger_usage(ledger), before)
  assert_true(quantity_configuration_matches(ledger, Some(zero_quantities())))
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
}
