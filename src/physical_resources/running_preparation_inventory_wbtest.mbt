///|
fn running_inventory_fixture() -> (
  Ledger,
  PreparationCapacity[Array[Int], Array[Int]],
  Array[Int],
  Array[Int],
  OriginalLedgerIdentity,
) {
  let ledger = create_ledger({
    planning_work: 100,
    attempts: 20,
    holdings: 20,
    transfer_bytes: 10000L,
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
    max_borrowers=2,
  ).unwrap()
  let identity = preparation_capacity_inventory_original(owner, input).unwrap()
  complete_preparation_capacity(owner, input, body, 100L, 50L).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  transfer_preparation_capacity_to_run(owner, input, body, ledger).unwrap()
  (ledger, owner, input, body, identity)
}

///|
test "running census growth preserves original tokens and cumulative history" {
  let (ledger, owner, input, body, identity) = running_inventory_fixture()
  let child = reserve_attempt(ledger, 7L, 10L, 11L).unwrap()
  let inventory = ledger.original_inventory.unwrap()
  let serial = ledger.next_attempt_serial
  grow_running_preparation_capacity_inventory(
    owner, input, body, identity, 200L, 100L, 4, 3, 2,
  ).unwrap()
  assert_true(physical_equal(ledger.original_inventory.unwrap(), inventory))
  assert_true(physical_equal(inventory.reservations.get(0), child))
  assert_eq(ledger.next_attempt_serial, serial)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 7L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 210L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 111L)
  assert_eq(inventory.max_reservations, 4)
  let usage = ledger_usage(ledger)
  grow_running_preparation_capacity_inventory(
    owner, input, body, identity, 200L, 100L, 4, 3, 2,
  ).unwrap()
  assert_eq(ledger_usage(ledger), usage)
}

///|
test "running census refuses wrong originals phase and nonmonotonic or overflowing demand" {
  let (ledger, owner, input, body, identity) = running_inventory_fixture()
  let (_, _, _, _, foreign) = running_inventory_fixture()
  for
    (actual_input, actual_body, actual_identity) in [
      ([1], body, identity),
      (input, [2], identity),
      (input, body, foreign),
    ] {
    assert_true(
      grow_running_preparation_capacity_inventory(
        owner, actual_input, actual_body, actual_identity, 200L, 100L, 4, 3, 2,
      )
      is Err(ForeignOriginal),
    )
  }
  for
    (r, e, reservations, holdings, delegations) in [
      (99L, 50L, 2, 0, 0),
      (100L, 49L, 2, 0, 0),
      (100L, 50L, 1, 0, 0),
      (100L, 50L, 2147483647, 1, 0),
      (100L, 50L, -1, 0, 0),
    ] {
    assert_true(
      grow_running_preparation_capacity_inventory(
        owner, input, body, identity, r, e, reservations, holdings, delegations,
      )
      is Err(InvalidExtent),
    )
  }
  owner.phase = Ready
  assert_true(
    grow_running_preparation_capacity_inventory(
      owner, input, body, identity, 200L, 100L, 4, 3, 2,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
}

///|
test "running census growth refuses closing parked and cleanup pending originals" {
  for mode in 0..<3 {
    let (ledger, owner, input, body, identity) = running_inventory_fixture()
    let inventory = ledger.original_inventory.unwrap()
    if mode == 0 {
      inventory.closing = true
    } else if mode == 1 {
      inventory.park = Some({ identity, })
    } else {
      mark_cleanup_pending(ledger, owner.reservation.reservation).unwrap()
    }
    let usage = ledger_usage(ledger)
    assert_true(
      grow_running_preparation_capacity_inventory(
        owner, input, body, identity, 200L, 100L, 4, 3, 2,
      )
      is Err(ForeignOriginal),
    )
    assert_eq(ledger_usage(ledger), usage)
    assert_eq(inventory.max_reservations, 2)
  }
}

///|
test "running census backing refusal leaves prefix custody and slot ceiling unchanged" {
  let (ledger, owner, input, body, identity) = running_inventory_fixture()
  let child = reserve_attempt(ledger, 7L, 10L, 11L).unwrap()
  let usage = ledger_usage(ledger)
  assert_true(
    grow_running_preparation_capacity_inventory(
      owner, input, body, identity, 10000L, 100L, 4, 3, 2,
    )
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.original_inventory.unwrap().max_reservations, 2)
  assert_true(reservation_open(child))
}

///|
test "running census rechecks callback retirement and nested growth before allocation" {
  for retire in [true, false] {
    let (ledger, owner, input, body, identity) = running_inventory_fixture()
    let entered = Ref(false)
    let callbacks = Ref(0)
    let nested_refused = Ref(false)
    let origin : ImportedChildLedgerOrigin = {
      nonce: 1L,
      admit: _ => 0,
      current: _ => {
        callbacks.val += 1
        if !entered.val {
          entered.val = true
          if retire {
            ledger.original_inventory.unwrap().closing = true
          } else {
            nested_refused.val = grow_running_preparation_capacity_inventory(
              owner, input, body, identity, 300L, 150L, 5, 4, 3,
            ) is Err(WorkActive)
          }
        }
        0
      },
      limit: (_, _) => 0L,
      capacity: (_, _) => 0L,
      report: (_, _) => 0,
      stop: _ => 0,
      fixed_capacities: false,
      working: None,
      ledger: Some(ledger),
      stopping: false,
      unavailable: false,
    }
    ledger.imported_child = Some(origin)
    let result = grow_running_preparation_capacity_inventory(
      owner, input, body, identity, 200L, 100L, 4, 3, 2,
    )
    assert_false(owner.inventory_growth_active)
    if retire {
      assert_true(
        result is Err(ForeignOriginal) ||
        result is Err(Resource(ClosedReservation)),
      )
      assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
      assert_eq(ledger.original_inventory.unwrap().max_reservations, 2)
      assert_eq(callbacks.val, 1)
    } else {
      assert_true(nested_refused.val)
      assert_true(result is Ok(_))
      assert_eq(ledger_usage(ledger).reserved_retention_bytes, 200L)
      assert_eq(ledger.original_inventory.unwrap().max_reservations, 4)
      assert_eq(callbacks.val, 1)
    }
  }
}

///|
test "running census refuses zero-byte new slots after imported parent stopping" {
  let (ledger, owner, input, body, identity) = running_inventory_fixture()
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    ledger: Some(ledger),
    stopping: true,
    unavailable: false,
  })
  let usage = ledger_usage(ledger)
  assert_true(
    grow_running_preparation_capacity_inventory(
      owner, input, body, identity, 100L, 50L, 4, 3, 2,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(ledger.original_inventory.unwrap().max_reservations, 2)
  assert_eq(calls.val, 0)
}

///|
// Return only the adopted holders and body. The generic input/capacity aliases
// do not escape this actual adoption boundary into the Run caller.
fn adopted_running_inventory_fixture() -> (
  Ledger, PreparationBodyBorrow[Array[Int]], PreparationBodyBorrow[Array[Int]],
  PreparationRetirement, Array[Int], OriginalLedgerIdentity,
) raise {
  let ledger = create_ledger({planning_work:100, attempts:20, holdings:20,
    transfer_bytes:10000L, retained_bytes:10000L, execution_bytes:10000L}).unwrap()
  let input = [1]
  let body = [2]
  let owner : PreparationCapacity[Array[Int], Array[Int]] =
    reserve_preparation_capacity_inventory(ledger, input, 100L, 50L, max_borrowers=2).unwrap()
  let identity = preparation_capacity_inventory_original(owner, input).unwrap()
  complete_preparation_capacity(owner, input, body, 100L, 50L).unwrap()
  claim_original_ledger_run_binding(identity, ledger).unwrap()
  let (retirement, holder, run_holder) = transfer_preparation_adoption_holders(
    owner, input, body, ledger, () => Ok(()),
  ).unwrap()
  assert_true(owner.retirement_claimed)
  (ledger, holder, run_holder, retirement, body, identity)
}

///|
test "adopted Run grows through retained holder after Request aliases are dropped" {
  let (ledger, holder, run_holder, retirement, body, identity) = adopted_running_inventory_fixture()
  grow_preparation_body_inventory(run_holder, body, identity, 200L, 100L, 4, 3, 2).unwrap()
  assert_eq(ledger.original_inventory.unwrap().max_reservations, 4)
  assert_true(grow_preparation_body_inventory(run_holder, [2], identity, 300L, 150L, 5, 4, 3) is Err(_))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_true(grow_preparation_body_inventory(run_holder, body, identity, 300L, 150L, 5, 4, 3) is Err(_))
  assert_false(return_preparation_body_borrow(holder).unwrap())
  // Run cleanup must acknowledge its original census separately from holders.
  assert_false(return_preparation_body_borrow(run_holder).unwrap())
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(retire_transferred_preparation(retirement).unwrap())
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  assert_true(grow_preparation_body_inventory(run_holder, body, identity, 300L, 150L, 5, 4, 3) is Err(_))
}

///|
test "adopted Run growth rechecks callback retirement and exact holder return" {
  for retire in [true, false] {
    let (ledger, holder, run_holder, retirement, body, identity) = adopted_running_inventory_fixture()
    let entered = Ref(false)
    ledger.imported_child = Some({
      nonce:1L, admit:_ => 0,
      current:_ => {
        if !entered.val {
          entered.val = true
          if retire { retire_transferred_preparation(retirement) |> ignore }
          else { return_preparation_body_borrow(run_holder) |> ignore }
        }
        0
      },
      limit:(_, _) => 0L, capacity:(_, _) => 0L, report:(_, _) => 0,
      stop:_ => 0, fixed_capacities:false, working:None, ledger:Some(ledger),
      stopping:false, unavailable:false,
    })
    assert_true(grow_preparation_body_inventory(run_holder, body, identity, 200L, 100L, 4, 3, 2) is Err(_))
    assert_eq(ledger.original_inventory.unwrap().max_reservations, 2)
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
    assert_true(preparation_body_borrow_value(holder) is Some(_) || preparation_body_retirement_started(holder))
  }
}

///|
test "running inventory entry carriers are fixed before variable admission" {
  let units = preparation_inventory_growth_entry_construction()
  assert_eq(units.record_headers, 10L)
  assert_eq(units.reference_slots, 10L)
  assert_eq(units.scalar_words, 16L)
  assert_true(physical_equal(units, preparation_inventory_growth_entry_construction()))
}

///|
test "adopted holder fences nested entry before another current callback and clears on return" {
  let (ledger, _, run_holder, _, body, identity) = adopted_running_inventory_fixture()
  let callbacks = Ref(0)
  let refused = Ref(false)
  ledger.imported_child = Some({
    nonce: 1L, admit: _ => 0,
    current: _ => {
      callbacks.val += 1
      refused.val = grow_preparation_body_inventory(
        run_holder, body, identity, 300L, 150L, 5, 4, 3,
      ) is Err(WorkActive)
      0
    },
    limit: (_, _) => 0L, capacity: (_, _) => 0L, report: (_, _) => 0,
    stop: _ => 0, fixed_capacities: false, working: None, ledger: Some(ledger),
    stopping: false, unavailable: false,
  })
  grow_preparation_body_inventory(run_holder, body, identity, 200L, 100L, 4, 3, 2).unwrap()
  assert_true(refused.val)
  assert_eq(callbacks.val, 1)
  assert_eq(ledger.original_inventory.unwrap().max_reservations, 4)
  grow_preparation_body_inventory(run_holder, body, identity, 300L, 150L, 5, 4, 3).unwrap()
  assert_eq(callbacks.val, 2)
  assert_eq(ledger.original_inventory.unwrap().max_reservations, 5)
}
