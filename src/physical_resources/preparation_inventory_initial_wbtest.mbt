///|
test "atomic preparation census owns one first token with no fabricated execution allowance" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(owner, input).unwrap()
  assert_eq(ledger_usage(ledger).live_reservations, 1)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_false(original_ledger_inventory_available(identity))
  assert_true(
    claim_original_ledger_run_binding(identity, ledger) is Err(InvalidBootstrap),
  )
  grow_preparation_capacity_inventory(owner, input, 800L, 20L, 2, 0, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "initial census shape belongs to Resource while prices remain outside it" {
  assert_true(
    preparation_inventory_initial_control_slots(6, 0, 0)
    is Some((19L, 28L, 22L)),
  )
  assert_true(preparation_inventory_initial_control_slots(-1, 0, 0) is None)
  assert_true(
    preparation_inventory_initial_control_slots(2147483647, 1, 0) is None,
  )
}

///|
test "unused preparation inventory disposal preserves input borrowers debit and consumed history" {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 3,
    holdings: 0,
    transfer_bytes: 20L,
    retained_bytes: 1000L,
    execution_bytes: 1000L,
  }).unwrap()
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    0L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(owner, input).unwrap()
  let operation = begin_preparation_io(owner, input, 3L).unwrap()
  charge_preparation_io(operation, 2L).unwrap()
  assert_true(
    discard_unbound_preparation_capacity_inventory(owner, input)
    is Err(WorkActive),
  )
  finish_preparation_io_after_cleanup(operation).unwrap()
  charge_planning(ledger, 2).unwrap()
  let holder = reserve_preparation_construction_input(
    owner,
    input,
    [2],
    800L,
    20L,
  ).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  discard_unbound_preparation_capacity_inventory(owner, input).unwrap()
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_true(ledger.original_inventory is None)
  assert_false(original_ledger_inventory_available(identity))
  assert_true(
    issue_recorded_original_ledger_descriptor(identity, [3])
    is Err(IncompleteInventory),
  )
  assert_true(preparation_body_borrow_value(holder) is Some(_))
  assert_false(return_preparation_body_borrow(holder).unwrap())
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
  assert_eq(ledger_usage(ledger).planning_work, 2)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
}

///|
test "atomic initial current reentry cannot leave an orphan first preparation reservation" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let selected : Ref[CapacityReservation?] = Ref(None)
  let calls = Ref(0)
  let action = Ref(
    Some(() => selected.val = Some(reserve_capacity(ledger, 0L, 0L).unwrap())),
  )
  preparation_inventory_observe_current(ledger, action, calls)
  let result : Result[
    PreparationCapacity[Array[Int], Unit],
    PreparationCapacityIssue,
  ] = reserve_preparation_capacity_inventory(
    ledger,
    [1],
    800L,
    0L,
    max_borrowers=2,
  )
  assert_true(result is Err(Resource(InvalidCharge)))
  // Atomic entrance and explicitly entered reentrant reserve are distinct
  // operations. The new entrance never debited a second, unreachable token.
  assert_eq(calls.val, 2)
  assert_eq(ledger_usage(ledger).live_reservations, 1)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(ledger.original_inventory is None)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  settle_capacity(ledger, selected.val.unwrap()).unwrap()
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "unused census disposal cannot erase a bound or quiescent Model identity" {
  let ledger = read_capacity_fixture(1000L, 1000L)
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    800L,
    20L,
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(owner, input).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    discard_unbound_preparation_capacity_inventory(owner, input)
    is Err(WorkActive),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(
    discard_unbound_preparation_capacity_inventory(owner, input)
    is Err(WorkActive),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
}
