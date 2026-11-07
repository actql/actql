///|
test "shared captured inputs borrow exact originals after retained preparation without resetting history" {
  let ledger = create_ledger({
    planning_work: 100,
    attempts: 12,
    holdings: 8,
    transfer_bytes: 10L,
    retained_bytes: 10000L,
    execution_bytes: 10000L,
  }).unwrap()
  let input = [1]
  let body = [2]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    100L,
    50L,
    max_borrowers=12,
  ).unwrap()
  grow_preparation_capacity_inventory(owner, input, 200L, 100L, 12, 8, 0).unwrap()
  configure_quantities(ledger, {
    tokens: 10L,
    cost_units: 0L,
    duration_ms: 10L,
  }).unwrap()
  // This real input operation starts before Run binding and remains held by
  // its original preparation borrower. It is not a captured Source token.
  let preparation = begin_preparation_io(owner, input, 1L).unwrap()
  charge_preparation_io(preparation, 1L).unwrap()
  complete_preparation_capacity(owner, input, body, 200L, 100L).unwrap()
  let identity = preparation_capacity_inventory_original(owner, input).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  let controls = reserve_capacity(ledger, 4L, 4L).unwrap()
  let originals = []
  for _ in 0..<2 {
    let reservation = reserve_attempt(
      ledger,
      0L,
      1L,
      1L,
      quantities=quantity_neutral_amounts(ledger),
    ).unwrap()
    let holding = retain_allocation(ledger, reservation, 1L).unwrap()
    settle_reservation(ledger, reservation).unwrap()
    originals.push((reservation, holding))
  }
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  assert_true(original_borrowed_captured_inputs_available(ledger, originals))
  assert_false(original_captured_inputs_prefix_available(ledger, originals))
  assert_eq(
    ledger.original_inventory.unwrap().reservations.get(0).serial,
    preparation.reservation.serial,
  )
  assert_eq(
    ledger.original_inventory.unwrap().reservations.get(2).serial,
    originals[0].0.serial,
  )
  assert_eq(
    ledger.original_inventory.unwrap().holdings.get(0).serial,
    originals[0].1.serial,
  )
  for
    invalid in [
      [],
      [originals[1], originals[0]],
      [originals[0], originals[0]],
      [(originals[0].0, originals[1].1), (originals[1].0, originals[0].1)],
    ] {
    assert_false(original_borrowed_captured_inputs_available(ledger, invalid))
  }
  let (foreign, _, other) = original_captured_inputs_fixture()
  assert_false(
    original_borrowed_captured_inputs_available(ledger, [other[0], originals[1]]),
  )
  assert_false(original_borrowed_captured_inputs_available(foreign, originals))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(quantity_usage(ledger), quantities)
  // 200 preparation + 4 controls + 2 captured bytes leave 9794 of 10000.
  assert_true(
    reserve_attempt(
      ledger,
      0L,
      9795L,
      0L,
      quantities=quantity_neutral_amounts(ledger),
    )
    is Err(RetentionLimit),
  )
  assert_eq(ledger_usage(ledger), before)
  let prefix = reserve_attempt(
    ledger,
    0L,
    2L,
    2L,
    quantities=quantity_neutral_amounts(ledger),
  ).unwrap()
  assert_true(original_borrowed_reservation_available(identity, ledger, prefix))
  mark_cleanup_pending(ledger, prefix).unwrap()
  assert_false(
    original_borrowed_reservation_available(identity, ledger, prefix),
  )
  let pending = ledger_usage(ledger)
  assert_true(original_borrowed_captured_inputs_available(ledger, originals))
  assert_eq(ledger_usage(ledger), pending)
  settle_reservation(ledger, prefix).unwrap()
  release_allocation(ledger, originals[0].1).unwrap()
  assert_false(original_borrowed_captured_inputs_available(ledger, originals))
  assert_false(
    original_borrowed_reservation_available(identity, ledger, prefix),
  )
  release_allocation(ledger, originals[1].1).unwrap()
  finish_preparation_io_after_cleanup(preparation).unwrap()
  settle_capacity(ledger, controls).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(retire_preparation_capacity(owner).unwrap())
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(quantity_usage(ledger), quantities)
  original_captured_inputs_release(foreign, other)
}
