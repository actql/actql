///|
test "stopping original preparation permits cleanup but never new admission" {
  let status = Ref(0)
  let child = prepare_imported_child_port(
    1L,
    _ => 0,
    _ => status.val,
    (_, _) => 1000L,
    (_, _) => 0L,
    (_, _) => 0,
    _ => 0,
    fixed_capacities=false,
  ).unwrap()
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(child, input, () => Ok(()))
  let ledger = start_node_preparation_admission(initial).unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=2,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  let (run, _, retirement, run_holder) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  status.val = 1
  assert_false(child.origin.stopping)
  assert_true(check_node_preparation_cleanup_original(run, ledger) is Ok(_))
  assert_true(child.origin.stopping)
  assert_true(check_node_managed_run_admission(run, ledger) is Err(Unavailable))
  assert_true(node_preparation_usage_isolated(run, ledger))
  assert_true(reserve_capacity(ledger, 1L, 0L) is Err(ClosedReservation))
  let foreign_initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let foreign = start_node_preparation_admission(foreign_initial).unwrap()
  assert_true(
    check_node_preparation_cleanup_original(run, foreign)
    is Err(ForeignOriginal),
  )
  assert_false(node_preparation_usage_isolated(run, foreign))
  cleanup_node_preparation_admission(foreign_initial).unwrap()
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_false(return_preparation_body_borrow(run_holder).unwrap())
  assert_true(release_node_preparation_holder(run).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  cleanup_node_managed_run_admission(run).unwrap()
  assert_true(
    check_node_preparation_cleanup_original(run, ledger) is Err(Unavailable),
  )
}

///|
test "unavailable original preparation remains retained and cannot authorize cleanup cut" {
  let child = preparation_adoption_child()
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(child, input, () => Ok(()))
  let ledger = start_node_preparation_admission(initial).unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=2,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  let (run, _, _, run_holder) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  child.origin.unavailable = true
  assert_true(
    check_node_preparation_cleanup_original(run, ledger)
    is Err(Resource(ChildFundingUnavailable)),
  )
  assert_false(node_preparation_usage_isolated(run, ledger))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_true(run.prepared is Some(_))
  assert_true(preparation_body_borrow_value(run_holder) is Some(_))
}

///|
// Actual Resource/adoption/quantity owners with the existing nominal imported
// child ports. Explicit attempt settlement is a fixture physical-stop witness,
// not ordinary Model IO, a provider ACK or a replacement quantity observation.
test "settled unknown Model quantities do not pin preparation or reset same parent history" {
  for census in [false, true] {
    let input = [1]
    let body = [2]
    let initial = prepare_node_preparation_original(
      preparation_adoption_child(),
      input,
      () => Ok(()),
    )
    let ledger = start_node_preparation_admission(initial).unwrap()
    let amounts : QuantityAmounts = {
      tokens: 33L,
      cost_units: 0L,
      duration_ms: 500L,
    }
    configure_quantities(ledger, amounts).unwrap()
    let capacity : PreparationCapacity[Array[Int], Array[Int]] = if census {
      let value = reserve_preparation_capacity_inventory(
        ledger,
        input,
        50L,
        70L,
        max_borrowers=2,
      ).unwrap()
      grow_preparation_capacity_inventory(value, input, 50L, 70L, 8, 2, 2).unwrap()
      value
    } else {
      reserve_preparation_capacity(ledger, input, 40L, 60L, max_borrowers=2).unwrap()
    }
    let (retained, execution) = if census { (40L, 10L) } else { (30L, 0L) }
    complete_preparation_capacity(capacity, input, body, retained, execution).unwrap()
    let (run, same, retirement, run_holder) = adopt_node_preparation_admission(
      initial, input, capacity, body,
    ).unwrap()
    assert_true(physical_equal(ledger, same))
    let attempt = reserve_attempt(ledger, 19L, 0L, 0L, quantities=Some(amounts)).unwrap()
    assert_false(node_preparation_usage_isolated(run, ledger))
    assert_eq(quantity_usage(ledger).reserved, amounts)
    mark_quantities_uncertain(ledger, attempt).unwrap()
    observe_quantities(ledger, attempt, tokens=Some(3L), cost_units=Some(0L)).unwrap()
    mark_transfer_uncertain(ledger, attempt, 19L).unwrap()
    mark_cleanup_pending(ledger, attempt).unwrap()
    assert_false(node_preparation_usage_isolated(run, ledger))
    // Only the same original physical child's explicit settlement removes its
    // live reservation. It does not turn unobserved duration into zero.
    settle_reservation(ledger, attempt).unwrap()
    let history = quantity_usage(ledger)
    assert_eq(history.reserved, zero_quantities())
    assert_eq(history.consumed.tokens, 3L)
    assert_eq(history.uncertain.duration_ms, 500L)
    assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 19L)
    assert_true(node_preparation_usage_isolated(run, ledger))
    assert_true(configure_quantities(ledger, amounts) is Err(InvalidCharge))
    assert_true(
      reserve_attempt(
        ledger,
        0L,
        0L,
        0L,
        quantities=Some({ ..zero_quantities(), duration_ms: 1L, }),
      )
      is Err(DurationLimit),
    )
    // The original imported child declares 1000 transfer bytes. Previously
    // dispatched uncertainty still consumes that SAME cumulative budget.
    assert_true(
      reserve_attempt(
        ledger,
        1000L,
        0L,
        0L,
        quantities=quantity_neutral_amounts(ledger),
      )
      is Err(TransferLimit),
    )
    // A separate zero-byte child/holding remains an actual identity even when
    // every historical quantity has already moved out of reserved usage.
    let neutral = reserve_attempt(
      ledger,
      0L,
      0L,
      0L,
      quantities=quantity_neutral_amounts(ledger),
    ).unwrap()
    assert_false(node_preparation_usage_isolated(run, ledger))
    let holding = retain_allocation(ledger, neutral, 0L).unwrap()
    settle_reservation(ledger, neutral).unwrap()
    assert_false(node_preparation_usage_isolated(run, ledger))
    release_allocation(ledger, holding).unwrap()
    assert_true(node_preparation_usage_isolated(run, ledger))
    assert_eq(quantity_usage(ledger), history)
    // The two original preparation borrowers still own retirement in order.
    assert_false(retire_transferred_preparation(retirement).unwrap())
    assert_false(return_preparation_body_borrow(run_holder).unwrap())
    assert_true(release_node_preparation_holder(run).unwrap())
    assert_true(retire_transferred_preparation(retirement).unwrap())
    assert_eq(cleanup_node_managed_run_admission(run), Ok(()))
    assert_eq(ledger_usage(ledger).live_reservations, 0)
    assert_eq(ledger_usage(ledger).holdings, 0)
    assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 19L)
    assert_eq(quantity_usage(ledger), history)
  }
}
