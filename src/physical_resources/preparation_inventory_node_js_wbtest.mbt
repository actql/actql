///|
test "same preparation census survives actual Node adoption and both original cleanup holders" {
  let child = preparation_adoption_child()
  let input = [1]
  let initial = prepare_node_preparation_original(child, input, () => Ok(()))
  let ledger = start_node_preparation_admission(initial).unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    30L,
    max_borrowers=2,
  ).unwrap()
  let original = capacity.reservation
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  let body = [2]
  complete_preparation_capacity(capacity, input, body, 40L, 30L).unwrap()
  let (run, same, retirement, run_holder) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_true(physical_equal(ledger, same))
  assert_true(physical_equal(run.child, child))
  assert_true(run.read_bootstrap is None)
  assert_true(
    ledger.original_inventory is Some(census) &&
    physical_equal(census.bootstrap, original),
  )
  assert_eq(ledger_usage(ledger).live_reservations, 1)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_true(node_preparation_usage_isolated(run, ledger))
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(cleanup_node_managed_run_admission(run) is Err(Unavailable))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_true(borrow_preparation_body_sibling(run_holder) is Err(Retired))
  assert_false(return_preparation_body_borrow(run_holder).unwrap())
  assert_true(capacity_reservation_open(original))
  assert_true(release_node_preparation_holder(run).unwrap())
  assert_false(capacity_reservation_open(original))
  assert_true(ledger.original_inventory is None)
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  cleanup_node_managed_run_admission(run).unwrap()
  assert_true(run.cleaned)
}
