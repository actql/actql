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

///|
test "preparation census and bootstrap transfer with the same original child and purpose" {
  let child = preparation_adoption_child()
  let input = [1]
  let body = [2]
  let initial : NodePreparationAdmission[Array[Int]] = {
    admission: Some(
      prepare_node_managed_run_original(
        child,
        input,
        () => Ok(()),
        purpose=LocalMockModel,
      ),
    ),
    transitioning: false,
  }
  let ledger = start_node_preparation_admission(initial).unwrap()
  let identity = begin_node_preparation_inventory(
    initial, input, 10L, 10L, 2, 0, 0,
  ).unwrap()
  let bootstrap = initial.admission.unwrap().read_bootstrap.unwrap()
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=1,
  ).unwrap()
  reserve_working_preparation_phase(capacity, input, 50L, 70L).unwrap()
  assert_eq(ledger.original_inventory.unwrap().reservations.length(), 1)
  assert_eq(ledger.next_capacity_serial, Some(-3))
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  let (run, same, retirement) = adopt_node_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_true(physical_equal(ledger, same))
  assert_true(physical_equal(run.child, child))
  assert_true(physical_equal(run.read_bootstrap.unwrap(), bootstrap))
  check_node_local_mock_model_run_preparation(run, body).unwrap()
  assert_true(
    check_node_source_compute_run_preparation(run, body) is Err(Unavailable),
  )
  assert_true(original_ledger_inventory_available(identity))
  assert_eq(ledger.next_capacity_serial, Some(-3))
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_true(node_preparation_usage_isolated(run, ledger))
  let other = reserve_capacity(ledger, 0L, 0L).unwrap()
  assert_false(node_preparation_usage_isolated(run, ledger))
  settle_capacity(ledger, other).unwrap()
  assert_true(node_preparation_usage_isolated(run, ledger))
  assert_true(cleanup_node_managed_run_admission(run) is Err(Unavailable))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_true(release_node_preparation_holder(run).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 10L)
  cleanup_node_managed_run_admission(run).unwrap()
  assert_false(capacity_reservation_open(bootstrap))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger.next_capacity_serial, Some(-4))
}

///|
test "preparation census refuses late or foreign input and retains original cleanup" {
  let input = [1]
  let initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let ledger = start_node_preparation_admission(initial).unwrap()
  assert_true(
    begin_node_preparation_inventory(initial, [1], 10L, 10L, 2, 0, 0)
    is Err(ForeignOriginal),
  )
  assert_eq(ledger.next_capacity_serial, Some(-1))
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=1,
  ).unwrap()
  assert_true(
    begin_node_preparation_inventory(initial, input, 10L, 10L, 2, 0, 0)
    is Err(Resource(InvalidCharge)),
  )
  assert_true(ledger.original_inventory is None)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  cleanup_node_preparation_admission(initial).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "preparation census initialization failure keeps its bootstrap on the original admission" {
  let input = [1]
  let initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let ledger = start_node_preparation_admission(initial).unwrap()
  assert_true(
    begin_node_preparation_inventory(initial, input, 10L, 10L, -1, 0, 0)
    is Err(Unavailable),
  )
  assert_true(initial.admission.unwrap().read_bootstrap is Some(_))
  assert_true(ledger.original_inventory is None)
  assert_true(
    begin_node_preparation_inventory(initial, input, 10L, 10L, 2, 0, 0)
    is Err(AlreadyConsumed),
  )
  cleanup_node_preparation_admission(initial).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "preparation adoption rechecks original census closing after its final current callback" {
  let active : Ref[PreparationCapacity[Array[Int], Array[Int]]?] = Ref(None)
  let held : Ref[Ledger?] = Ref(None)
  let closed = Ref(false)
  let child = prepare_imported_child_port(
    1L,
    _ => 0,
    _ => {
      if !closed.val &&
        active.val is Some(capacity) &&
        capacity.phase == Transferring &&
        held.val is Some(ledger) {
        closed.val = true
        closed.val = finish_original_ledger_inventory(ledger, true) == Ok(false)
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
  let ledger = start_node_preparation_admission(initial).unwrap()
  held.val = Some(ledger)
  begin_node_preparation_inventory(initial, input, 10L, 10L, 2, 0, 0).unwrap()
  |> ignore
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    60L,
    max_borrowers=1,
  ).unwrap()
  active.val = Some(capacity)
  complete_preparation_capacity(capacity, input, body, 30L, 0L).unwrap()
  assert_true(
    adopt_node_preparation_admission(initial, input, capacity, body)
    is Err(Resource(ClosedReservation)),
  )
  assert_true(closed.val)
  assert_true(initial.admission is Some(_))
  assert_true(capacity.phase == Ready)
  assert_eq(capacity.borrowers, 0)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_true(retire_preparation_capacity(capacity).unwrap())
  cleanup_node_preparation_admission(initial).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
fn zero_byte_preparation_isolation_fixture(
  census : Bool,
) -> (NodeManagedRunAdmission[Array[Int]], Ledger, PreparationRetirement) {
  let input = [1]
  let body = [2]
  let initial = prepare_node_preparation_original(
    preparation_adoption_child(),
    input,
    () => Ok(()),
  )
  let ledger = start_node_preparation_admission(initial).unwrap()
  if census {
    begin_node_preparation_inventory(initial, input, 10L, 10L, 8, 2, 2).unwrap()
    |> ignore
  }
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
  (run, ledger, retirement)
}

///|
test "zero-byte isolation retains a real holding after its reservation closes without refunding spent work" {
  for census in [false, true] {
    let (run, ledger, retirement) = zero_byte_preparation_isolation_fixture(
      census,
    )
    charge_planning(ledger, 1).unwrap()
    let before = ledger_usage(ledger)
    let operation = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
    consume_reserved_attempt(ledger, operation).unwrap()
    let holding = retain_allocation(ledger, operation, 0L).unwrap()
    settle_reservation(ledger, operation).unwrap()
    let held = ledger_usage(ledger)
    assert_eq(held.live_reservations, before.live_reservations)
    assert_eq(held.reserved_retention_bytes, before.reserved_retention_bytes)
    assert_eq(held.reserved_execution_bytes, before.reserved_execution_bytes)
    assert_eq(held.held_bytes, 0L)
    assert_eq(held.holdings, 1)
    assert_false(node_preparation_usage_isolated(run, ledger))
    release_allocation(ledger, holding).unwrap()
    assert_true(node_preparation_usage_isolated(run, ledger))
    assert_eq(ledger_usage(ledger).planning_work, 1)
    assert_eq(ledger_usage(ledger).attempts, 1)
    assert_false(retire_transferred_preparation(retirement).unwrap())
    release_node_preparation_holder(run).unwrap() |> ignore
    cleanup_node_managed_run_admission(run).unwrap()
    assert_eq(ledger_usage(ledger).planning_work, 1)
    assert_eq(ledger_usage(ledger).attempts, 1)
  }
}

///|
test "zero-byte isolation retains an actual delegated child until settlement with cumulative attempt preserved" {
  for census in [false, true] {
    let (run, ledger, retirement) = zero_byte_preparation_isolation_fixture(
      census,
    )
    let before = ledger_usage(ledger)
    let limits : LedgerLimits = {
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    }
    let delegated = reserve_execution_delegation(ledger, limits, 0L, 0L).unwrap()
    consume_execution_delegation_attempt(ledger, delegated).unwrap()
    let live = ledger_usage(ledger)
    assert_eq(live.reserved_retention_bytes, before.reserved_retention_bytes)
    assert_eq(live.reserved_execution_bytes, before.reserved_execution_bytes)
    assert_eq(live.reserved_attempts, 0)
    assert_eq(live.live_delegations, 1)
    assert_false(node_preparation_usage_isolated(run, ledger))
    settle_execution_delegation(
      ledger,
      delegated,
      Some(ledger_usage(create_ledger(limits).unwrap())),
    ).unwrap()
    assert_true(node_preparation_usage_isolated(run, ledger))
    assert_eq(ledger_usage(ledger).attempts, 1)
    assert_false(retire_transferred_preparation(retirement).unwrap())
    release_node_preparation_holder(run).unwrap() |> ignore
    cleanup_node_managed_run_admission(run).unwrap()
    assert_eq(ledger_usage(ledger).attempts, 1)
    assert_eq(ledger_usage(ledger).live_delegations, 0)
  }
}
