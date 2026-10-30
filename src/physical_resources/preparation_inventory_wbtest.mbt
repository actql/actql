///|
// Independent logical byte/count fixtures for custody, not physical Model
// layout coefficients, installed admission or a provider/normal acceptance.
fn preparation_inventory_fixture(
  quantities? : QuantityAmounts? = None,
) -> (Ledger, Array[Int], PreparationCapacity[Array[Int], Array[Int]]) {
  let ledger = create_ledger({
    planning_work: 20,
    attempts: 3,
    holdings: 3,
    transfer_bytes: 100L,
    retained_bytes: 1000L,
    execution_bytes: 1000L,
  }).unwrap()
  if quantities is Some(amounts) {
    configure_quantities(ledger, amounts).unwrap()
  }
  let input = [1]
  let capacity : PreparationCapacity[Array[Int], Array[Int]] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    30L,
    max_borrowers=3,
  ).unwrap()
  (ledger, input, capacity)
}

///|
test "preparation census keeps the first reservation through Scope close and original borrower retirement" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let token = capacity.reservation
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  let census = ledger.original_inventory.unwrap()
  assert_true(physical_equal(census.bootstrap, token))
  assert_eq(ledger_usage(ledger).live_reservations, 1)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  charge_planning(ledger, 3).unwrap()
  grow_preparation_capacity_inventory(capacity, input, 80L, 60L, 2, 1, 0).unwrap()
  assert_true(physical_equal(ledger.original_inventory.unwrap(), census))
  assert_eq(ledger_usage(ledger).planning_work, 3)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  let body = [2]
  complete_preparation_capacity(capacity, input, body, 70L, 50L).unwrap()
  let holder = borrow_preparation_body(capacity).unwrap()
  let charged = ledger_usage(ledger)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(census.closing)
  assert_true(census.binding == PreparationQuiescent)
  assert_true(capacity_reservation_open(token))
  assert_eq(ledger_usage(ledger), charged)
  assert_true(
    preparation_body_borrow_value(holder) is Some(original) &&
    physical_equal(original, body),
  )
  assert_true(borrow_preparation_body(capacity) is Err(Retired))
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(ClosedReservation))
  assert_false(retire_preparation_capacity(capacity).unwrap())
  assert_true(return_preparation_body_borrow(holder).unwrap())
  assert_true(ledger.original_inventory is None)
  assert_false(capacity_reservation_open(token))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  assert_eq(ledger_usage(ledger).planning_work, 3)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_true(retire_preparation_capacity(capacity).unwrap())
}

///|
test "preparation census refuses late history and foreign or invalid early entrances" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let before = ledger_usage(ledger)
  assert_true(
    begin_preparation_capacity_inventory(capacity, [1], 0, 0, 0)
    is Err(ForeignOrigin),
  )
  assert_true(
    begin_preparation_capacity_inventory(capacity, input, -1, 0, 0)
    is Err(IncompleteInventory),
  )
  assert_true(
    begin_preparation_capacity_inventory(capacity, input, 2147483647, 1, 0)
    is Err(IncompleteInventory),
  )
  assert_eq(ledger_usage(ledger), before)
  charge_planning(ledger, 1).unwrap()
  assert_true(
    begin_preparation_capacity_inventory(capacity, input, 0, 0, 0)
    is Err(ChangedOriginalState),
  )
  assert_true(ledger.original_inventory is None)
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )

  let (ledger, input, capacity) = preparation_inventory_fixture()
  let zero = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, zero).unwrap()
  assert_true(
    begin_preparation_capacity_inventory(capacity, input, 0, 0, 0)
    is Err(InvalidBootstrap),
  )
  assert_eq(ledger.next_capacity_serial, Some(-3))
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "preparation census preserves zero byte children Unknown quantities and separate physical acknowledgement" {
  let amounts = { tokens: 3L, cost_units: 5L, duration_ms: 7L, }
  let (ledger, input, capacity) = preparation_inventory_fixture(
    quantities=Some(amounts),
  )
  let identity = begin_preparation_capacity_inventory(capacity, input, 1, 1, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  let send = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(amounts)).unwrap()
  let holding = retain_allocation(ledger, send, 0L).unwrap()
  mark_quantities_uncertain(ledger, send).unwrap()
  let unknown = quantity_usage(ledger)
  complete_preparation_capacity(capacity, input, [2], 40L, 30L).unwrap()
  assert_false(retire_preparation_capacity(capacity).unwrap())
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  settle_reservation(ledger, send).unwrap()
  assert_false(finish_original_ledger_inventory(ledger, true).unwrap())
  release_allocation(ledger, holding).unwrap()
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_false(retire_preparation_capacity(capacity).unwrap())
  assert_true(capacity_reservation_open(capacity.reservation))
  assert_eq(quantity_usage(ledger), unknown)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(retire_preparation_capacity(capacity).unwrap())
  assert_eq(quantity_usage(ledger), unknown)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger.next_attempt_serial, Some(1))
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "preparation census growth retains serials and refuses changed bounds or bound Run" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let identity = begin_preparation_capacity_inventory(capacity, input, 1, 0, 0).unwrap()
  let child = reserve_capacity(ledger, 0L, 0L).unwrap()
  settle_capacity(ledger, child).unwrap()
  charge_planning(ledger, 2).unwrap()
  let serial = ledger.next_capacity_serial
  let census = ledger.original_inventory.unwrap()
  grow_preparation_capacity_inventory(capacity, input, 80L, 60L, 2, 1, 0).unwrap()
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(ledger_usage(ledger).planning_work, 2)
  assert_true(physical_equal(ledger.original_inventory.unwrap(), census))
  assert_eq(census.reservations.slots.length(), 1)
  assert_true(census.reservations.slots[0] is None)
  assert_true(
    grow_preparation_capacity_inventory(capacity, input, 80L, 60L, 1, 1, 0)
    is Err(InvalidExtent),
  )
  assert_true(
    grow_preparation_capacity_inventory(
      capacity, input, 80L, 60L, 2147483647, 1, 0,
    )
    is Err(InvalidExtent),
  )
  let before = ledger_usage(ledger)
  assert_true(
    grow_preparation_capacity_inventory(capacity, input, 1001L, 60L, 3, 1, 0)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(census.max_reservations, 2)
  assert_eq(ledger_usage(ledger), before)
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  assert_true(
    grow_preparation_capacity_inventory(capacity, input, 80L, 60L, 3, 1, 0)
    is Err(WorkActive),
  )
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(
    reserve_working_preparation_phase(capacity, input, 81L, 60L)
    is Err(Resource(ClosedReservation)),
  )
  assert_true(
    reserve_preparation_construction_input(capacity, input, [2], 80L, 60L)
    is Err(Retired),
  )
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "preparation census follows the typed continuation without another reservation" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  let next : PreparationCapacity[Array[Int], String] = continue_preparation_capacity(
    capacity, input,
  ).unwrap()
  assert_true(physical_equal(capacity.reservation, next.reservation))
  grow_preparation_capacity_inventory(next, input, 80L, 60L, 1, 0, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  complete_preparation_capacity(next, input, "body", 70L, 50L).unwrap()
  let retired = transfer_preparation_retirement_to_run(
    next, input, "body", ledger,
  ).unwrap()
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input)
    is Err(ForeignOriginal),
  )
  assert_false(retire_transferred_preparation(retired).unwrap())
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(retire_transferred_preparation(retired).unwrap())
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}
