///|
test "original Model quantities install once after settled preparation input without resetting its ledger" {
  // Logical Resource limits only; not a provider/Host Model capacity recipe.
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let parent : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(parent, input).unwrap()
  let operation = begin_preparation_io(parent, input, 3L).unwrap()
  charge_preparation_io(operation, 2L).unwrap()
  finish_preparation_io_after_cleanup(operation).unwrap()
  charge_planning(ledger, 2).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_attempt_serial
  let amounts : QuantityAmounts = {
    tokens: 33L,
    cost_units: 7L,
    duration_ms: 19L,
  }
  assert_eq(configure_quantities(ledger, amounts), Ok(()))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_attempt_serial, serial)
  assert_true(quantity_configuration_matches(ledger, Some(amounts)))
  assert_eq(configure_quantities(ledger, amounts), Err(InvalidCharge))
  grow_preparation_capacity_inventory(parent, input, 800L, 20L, 2, 0, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(InvalidCharge))
  let model = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  mark_quantities_uncertain(ledger, model).unwrap()
  observe_quantities(
    ledger,
    model,
    tokens=Some(3L),
    cost_units=Some(0L),
    duration_ms=Some(2L),
  ).unwrap()
  settle_reservation(ledger, model).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
  assert_eq(quantity_usage(ledger).consumed, {
    tokens: 3L,
    cost_units: 0L,
    duration_ms: 2L,
  })
  assert_eq(ledger_usage(ledger).attempts, 2)
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).planning_work, 2)
}

///|
test "deferred Model quantities refuse live Unknown bound issued and raw preparation histories" {
  for condition in 0..<6 {
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
    let mut live : PreparationIo? = None
    match condition {
      0 => live = Some(begin_preparation_io(parent, input, 3L).unwrap())
      1 => {
        let operation = begin_preparation_io(parent, input, 3L).unwrap()
        mark_preparation_io_transfer_uncertain(operation).unwrap()
        finish_preparation_io_after_cleanup(operation).unwrap()
      }
      2 => claim_original_ledger_run_binding(identity, ledger).unwrap()
      3 =>
        issue_recorded_original_ledger_descriptor(identity, [1]).unwrap()
        |> ignore
      4 => {
        let token = reserve_capacity(ledger, 0L, 0L).unwrap()
        settle_capacity(ledger, token).unwrap()
      }
      _ => {
        let token = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
        settle_reservation(ledger, token).unwrap()
      }
    }
    let before = ledger_usage(ledger)
    let amounts : QuantityAmounts = {
      tokens: 1L,
      cost_units: 0L,
      duration_ms: 0L,
    }
    assert_eq(configure_quantities(ledger, amounts), Err(InvalidCharge))
    assert_eq(ledger_usage(ledger), before)
    assert_true(quantity_configuration_matches(ledger, None))
    if live is Some(operation) {
      finish_preparation_io_after_cleanup(operation).unwrap()
      // Only real completion of this known input changes the refusal. No
      // consumed work or failed business token is erased to make it fit.
      configure_quantities(ledger, amounts).unwrap()
    }
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    assert_true(
      abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
    )
    if condition == 1 {
      assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 3L)
    }
  }
}

///|
test "quantity current reentry cannot bind or spend the original census behind installation" {
  for bind_run in [false, true] {
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
    let calls = Ref(0)
    let action = Ref(
      Some(() => {
        if bind_run {
          claim_original_ledger_run_binding(identity, ledger).unwrap()
        } else {
          let token = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
          settle_reservation(ledger, token).unwrap()
        }
      }),
    )
    preparation_inventory_observe_current(ledger, action, calls)
    assert_eq(
      configure_quantities(ledger, zero_quantities()),
      Err(InvalidCharge),
    )
    assert_eq(calls.val, if bind_run { 1 } else { 3 })
    assert_true(quantity_configuration_matches(ledger, None))
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    assert_true(
      abort_preparation_capacity_after_cleanup(parent, input).unwrap(),
    )
  }
}

///|
test "reentrant quantity installation has one original winner and never overwrites its limits" {
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
  ignore(identity)
  let amounts : QuantityAmounts = {
    tokens: 1L,
    cost_units: 0L,
    duration_ms: 0L,
  }
  let calls = Ref(0)
  let action = Ref(Some(() => configure_quantities(ledger, amounts).unwrap()))
  preparation_inventory_observe_current(ledger, action, calls)
  assert_eq(
    configure_quantities(ledger, { ..amounts, tokens: 2L, }),
    Err(InvalidCharge),
  )
  assert_eq(calls.val, 2)
  assert_true(quantity_configuration_matches(ledger, Some(amounts)))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(parent, input).unwrap())
}
