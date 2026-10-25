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
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  let (run, _, retirement) = adopt_node_preparation_admission(
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
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  let (run, _, _) = adopt_node_preparation_admission(
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
}
