///|
fn preparation_adoption_child() -> ImportedChildLedger {
  prepare_imported_child_port(
    1L,
    _ => 0,
    _ => 0,
    (_, _) => 1000L,
    (_, _) => 0L,
    (_, _) => 0,
    _ => 0,
    fixed_capacities=false,
  ).unwrap()
}

///|
test "node preparation adoption preserves the one imported child and debit" {
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
  assert_eq(cleanup_node_preparation_admission(initial), Err(Unavailable))
  let (run, same, retirement) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_true(physical_equal(ledger, same))
  assert_true(physical_equal(run.child, child))
  assert_eq(ledger_usage(same).reserved_retention_bytes, 30L)
  assert_true(initial.admission is None)
  assert_eq(check_node_managed_run_preparation(run, body), Ok(()))
  assert_true(start_node_managed_run_admission(run) is Err(AlreadyConsumed))
  assert_true(
    adopt_node_preparation_admission(initial, input, capacity, body)
    is Err(AlreadyConsumed),
  )
  assert_eq(cleanup_node_preparation_admission(initial), Err(AlreadyConsumed))
  assert_eq(cleanup_node_managed_run_admission(run), Err(Unavailable))
  assert_eq(release_node_preparation_holder(run), Err(Unavailable))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_true(release_node_preparation_holder(run).unwrap())
  assert_true(retire_transferred_preparation(retirement).unwrap())
  assert_eq(cleanup_node_managed_run_admission(run), Ok(()))
  assert_true(run.prepared is None)
}

///|
test "node preparation adoption rejects foreign input body and sibling ledger" {
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let ledger = start_node_preparation_admission(initial).unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  assert_true(
    adopt_node_preparation_admission(initial, [1], capacity, body)
    is Err(ForeignOriginal),
  )
  assert_true(
    adopt_node_preparation_admission(initial, input, capacity, [2])
    is Err(ForeignOriginal),
  )
  let sibling = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  start_node_preparation_admission(sibling).unwrap() |> ignore
  assert_true(
    adopt_node_preparation_admission(sibling, input, capacity, body)
    is Err(ForeignOriginal),
  )
  assert_true(initial.admission is Some(_))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  let (run, _, retirement) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_false(retire_transferred_preparation(retirement).unwrap())
  release_node_preparation_holder(run).unwrap() |> ignore
  cleanup_node_managed_run_admission(run).unwrap()
  cleanup_node_preparation_admission(sibling).unwrap()
}

///|
test "node preparation adoption refuses touched stop report and bootstrap custody" {
  let input = [1]
  let body = [2]
  let child = preparation_adoption_child()
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
  child.pending_report = Some(ledger_usage(ledger))
  assert_true(
    adopt_node_preparation_admission(initial, input, capacity, body)
    is Err(Unavailable),
  )
  child.pending_report = None
  child.stop_attempted = true
  child.stop_outcome = Some(Unknown)
  assert_true(
    adopt_node_preparation_admission(initial, input, capacity, body)
    is Err(Unavailable),
  )
  child.stop_attempted = false
  child.stop_outcome = None
  let admission = initial.admission.unwrap()
  admission.read_bootstrap_attempted = true
  assert_true(
    adopt_node_preparation_admission(initial, input, capacity, body)
    is Err(Unavailable),
  )
  assert_true(initial.admission is Some(_))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_true(capacity.phase is Ready)
}

///|
test "node preparation adoption currentness reentry cannot acquire a second cleanup owner" {
  let slot : Array[NodePreparationAdmission[Array[Int]]?] = [None]
  let armed = [false]
  let observed = [0]
  let calls = [0]
  let child = prepare_imported_child_port(
    1L,
    _ => {
      calls[0] += 1
      0
    },
    _ => {
      if armed[0] {
        if slot[0] is Some(initial) {
          if cleanup_node_preparation_admission(initial) is Err(Unknown) {
            observed[0] += 1
          } else {
            observed[0] = -1000
          }
        }
      }
      0
    },
    (_, _) => 1000L,
    (_, _) => 0L,
    (_, _) => 0,
    _ => 0,
    fixed_capacities=false,
  ).unwrap()
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(child, input, () => Ok(()))
  slot[0] = Some(initial)
  let ledger = start_node_preparation_admission(initial).unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=1,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  armed[0] = true
  let (run, same, retirement) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  armed[0] = false
  assert_true(observed[0] >= 2)
  assert_eq(calls[0], 1)
  assert_true(physical_equal(same, ledger))
  assert_true(initial.admission is None)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_false(retire_transferred_preparation(retirement).unwrap())
  release_node_preparation_holder(run).unwrap() |> ignore
  cleanup_node_managed_run_admission(run).unwrap()
}

///|
test "node preparation adoption keeps an operation reader charged after admission holder clears" {
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let ledger = start_node_preparation_admission(initial).unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=2,
  ).unwrap()
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  let reader = borrow_preparation_body(capacity).unwrap()
  let (run, _, retirement) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_false(release_node_preparation_holder(run).unwrap())
  assert_true(run.prepared is None)
  assert_true(
    preparation_body_borrow_value(reader) is Some(original) &&
    physical_equal(original, body),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 30L)
  assert_eq(cleanup_node_managed_run_admission(run), Err(Unavailable))
  assert_true(
    borrow_preparation_body(capacity) is Err(PreparationCapacityIssue::Retired),
  )
  assert_true(return_preparation_body_borrow(reader).unwrap())
  assert_true(preparation_body_borrow_value(reader) is None)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  cleanup_node_managed_run_admission(run).unwrap()
}

///|
test "node preparation adoption isolation identifies only its original remaining debit" {
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
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
  assert_true(node_preparation_usage_isolated(run, ledger))
  let other = reserve_capacity(ledger, 1L, 0L).unwrap()
  assert_false(node_preparation_usage_isolated(run, ledger))
  settle_capacity(ledger, other).unwrap()
  assert_true(node_preparation_usage_isolated(run, ledger))
  let sibling = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let foreign = start_node_preparation_admission(sibling).unwrap()
  assert_false(node_preparation_usage_isolated(run, foreign))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  release_node_preparation_holder(run).unwrap() |> ignore
  assert_false(node_preparation_usage_isolated(run, ledger))
  cleanup_node_managed_run_admission(run).unwrap()
  cleanup_node_preparation_admission(sibling).unwrap()
}

///|
test "node preparation input rejects a foreign receipt before original child start" {
  let child = preparation_adoption_child()
  let input = [1]
  let initial = prepare_node_preparation_original(child, input, () => Ok(()))
  assert_eq(check_node_preparation_input(initial, input), Ok(()))
  assert_eq(check_node_preparation_input(initial, [1]), Err(ForeignOriginal))
  guard initial.admission is Some(admission) else { abort("original missing") }
  assert_false(admission.attempted)
  initial.transitioning = true
  assert_eq(check_node_preparation_input(initial, input), Err(Unknown))
  initial.transitioning = false
  assert_eq(check_node_preparation_input(initial, input), Ok(()))
}
