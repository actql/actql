///|
fn preparation_inventory_observe_current(
  ledger : Ledger,
  action : Ref[(() -> Unit)?],
  calls : Ref[Int],
) -> Unit {
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      if action.val is Some(run) {
        action.val = None
        run()
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
}

///|
test "preparation census reentry cannot release Scope or parent twice or borrow after closure" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  complete_preparation_capacity(capacity, input, [2], 40L, 30L).unwrap()
  let held = borrow_preparation_body(capacity).unwrap()
  let calls = Ref(0)
  let flags = Ref(0)
  let action = Ref(
    Some(() => {
      if finish_original_ledger_inventory(ledger, true) == Ok(false) {
        flags.val += 1
      }
      if retire_preparation_capacity(capacity) == Ok(false) {
        flags.val += 2
      }
      if borrow_preparation_body(capacity) is Err(Retired) {
        flags.val += 4
      }
    }),
  )
  preparation_inventory_observe_current(ledger, action, calls)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(calls.val, 1)
  assert_eq(flags.val, 7)
  assert_true(capacity_reservation_open(capacity.reservation))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(calls.val, 1)
  action.val = Some(() => {
    if retire_preparation_capacity(capacity) is Err(WorkActive) {
      flags.val += 8
    }
    if finish_original_ledger_inventory(ledger, true) == Ok(false) {
      flags.val += 16
    }
  })
  assert_true(return_preparation_body_borrow(held).unwrap())
  assert_eq(calls.val, 2)
  assert_eq(flags.val, 31)
  assert_true(ledger.original_inventory is None)
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "preparation census growth cannot publish slots after current binds the original Run" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  let calls = Ref(0)
  let bound = Ref(false)
  let action = Ref(
    Some(() => {
      if claim_original_ledger_run_binding(identity, ledger) == Ok(()) {
        bound.val = true
      }
    }),
  )
  preparation_inventory_observe_current(ledger, action, calls)
  assert_true(
    grow_preparation_capacity_inventory(capacity, input, 80L, 60L, 2, 1, 0)
    is Err(WorkActive),
  )
  assert_true(bound.val)
  assert_eq(calls.val, 1)
  let census = ledger.original_inventory.unwrap()
  assert_eq(census.max_reservations, 0)
  assert_eq(census.max_holdings, 0)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 80L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 60L)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}

///|
test "preparation census unresolved current keeps the original closed fence and debit" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  complete_preparation_capacity(capacity, input, [2], 40L, 30L).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => -41,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let before = ledger_usage(ledger)
  assert_true(
    retire_preparation_capacity(capacity)
    is Err(Resource(ChildFundingUnavailable)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(capacity_reservation_open(capacity.reservation))
  assert_true(
    ledger.original_inventory is Some(value) &&
    value.closing &&
    value.binding == PreparationQuiescent,
  )
  assert_true(capacity.phase == Retiring)
  assert_true(capacity.input is None && capacity.body is None)
}

///|
test "preparation census zero growth constructor cannot return an input after current closes its Scope" {
  let (ledger, input, capacity) = preparation_inventory_fixture()
  let identity = begin_preparation_capacity_inventory(capacity, input, 0, 0, 0).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  let calls = Ref(0)
  let closed = Ref(false)
  let action = Ref(
    Some(() => {
      if finish_original_ledger_inventory(ledger, true) == Ok(true) {
        closed.val = true
      }
    }),
  )
  preparation_inventory_observe_current(ledger, action, calls)
  assert_true(
    reserve_preparation_construction_input(capacity, input, [2], 40L, 30L)
    is Err(Retired),
  )
  // Two distinct entered operations: constructor reserve and reentrant Scope
  // finish. No second observation is added by the constructor's post-fence.
  assert_eq(calls.val, 2)
  assert_true(closed.val)
  assert_eq(capacity.borrowers, 0)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_true(capacity_reservation_open(capacity.reservation))
  assert_true(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}
