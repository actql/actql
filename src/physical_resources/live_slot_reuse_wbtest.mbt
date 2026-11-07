///|
fn live_slot_test_ledger() -> Ledger {
  create_ledger({
    planning_work: 10,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 3L,
    retained_bytes: 32L,
    execution_bytes: 16L,
  }).unwrap()
}

///|
test "transfer mutation has no second current callback after validating its original bound" {
  let ledger = live_slot_test_ledger()
  let reservation = reserve_attempt(ledger, 3L, 0L, 0L).unwrap()
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      if calls.val == 2 {
        charge_transfer(ledger, reservation, 2L).unwrap()
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  charge_transfer(ledger, reservation, 2L).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(reservation.transfer, 1L)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(calls.val, 1)
}

///|
test "reservation current callback cannot overwrite a nested original debit" {
  for capacity_only in [false, true] {
    let ledger = live_slot_test_ledger()
    let armed = Ref(true)
    let nested : Ref[Reservation?] = Ref(None)
    ledger.imported_child = Some({
      nonce: 1L,
      admit: _ => 0,
      current: _ => {
        if armed.val {
          armed.val = false
          nested.val = Some(reserve_attempt(ledger, 0L, 20L, 0L).unwrap())
        }
        0
      },
      limit: (_, _) => 0L,
      capacity: (_, _) => 0L,
      report: (_, _) => 0,
      stop: _ => 0,
      fixed_capacities: false,
      working: None,
      current_window: None,
      ledger: Some(ledger),
      stopping: false,
      unavailable: false,
    })
    if capacity_only {
      assert_true(reserve_capacity(ledger, 20L, 0L) is Err(RetentionLimit))
    } else {
      assert_true(reserve_attempt(ledger, 0L, 20L, 0L) is Err(RetentionLimit))
    }
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 20L)
    assert_eq(ledger_usage(ledger).reserved_attempts, 1)
    assert_eq(ledger_usage(ledger).live_reservations, 1)
    settle_reservation(ledger, nested.val.unwrap()).unwrap()
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  }
}

///|
test "delegation current callback cannot overwrite a nested original quota" {
  let ledger = create_ledger({ ..live_slot_test_ledger().limits, attempts: 3, }).unwrap()
  let child_limits : LedgerLimits = {
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  let armed = Ref(true)
  let nested : Ref[ExecutionDelegation?] = Ref(None)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        nested.val = Some(
          reserve_execution_delegation(ledger, child_limits, 0L, 0L).unwrap(),
        )
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_true(
    reserve_execution_delegation(ledger, child_limits, 0L, 0L)
    is Err(AttemptLimit),
  )
  assert_eq(ledger.delegated_attempts, 1)
  assert_eq(ledger_usage(ledger).reserved_attempts, 1)
  assert_eq(ledger_usage(ledger).live_delegations, 1)
  assert_true(nested.val is Some(_))
}

///|
test "cleanup current callback cannot settle or release the same original twice" {
  for release_holding in [false, true] {
    let ledger = live_slot_test_ledger()
    let reservation = reserve_attempt(ledger, 0L, 8L, 4L).unwrap()
    let holding = retain_allocation(ledger, reservation, 3L).unwrap()
    let armed = Ref(true)
    ledger.imported_child = Some({
      nonce: 1L,
      admit: _ => 0,
      current: _ => {
        if armed.val {
          armed.val = false
          if release_holding {
            release_allocation(ledger, holding).unwrap()
          } else {
            settle_reservation(ledger, reservation).unwrap()
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
      current_window: None,
      ledger: Some(ledger),
      stopping: false,
      unavailable: false,
    })
    if release_holding {
      assert_eq(release_allocation(ledger, holding), Err(ClosedHolding))
      assert_eq(ledger_usage(ledger).holdings, 0)
      assert_eq(ledger_usage(ledger).held_bytes, 0L)
      settle_reservation(ledger, reservation).unwrap()
    } else {
      assert_eq(settle_reservation(ledger, reservation), Err(ClosedReservation))
      assert_eq(ledger_usage(ledger).live_reservations, 0)
      assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
      assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
      release_allocation(ledger, holding).unwrap()
    }
    assert_eq(ledger_usage(ledger).holdings, 0)
    assert_eq(ledger_usage(ledger).held_bytes, 0L)
  }
}

///|
test "live slots allow 10000 settled cycles on the same Ledger without resetting identity" {
  let ledger = live_slot_test_ledger()
  let mut previous : (Reservation, Holding)? = None
  for cycle in 0..<10000 {
    let admitted = reserve_attempt(ledger, 0L, 4L, 2L)
    assert_true(
      admitted is Ok(_),
      msg="retired capacity must be reusable at cycle " + cycle.to_string(),
    )
    let reservation = admitted.unwrap()
    let holding = retain_allocation(ledger, reservation, 4L).unwrap()
    if previous is Some((old_reservation, old_holding)) {
      assert_true(old_reservation.serial != reservation.serial)
      assert_true(old_holding.serial != holding.serial)
      let before = ledger_usage(ledger)
      assert_eq(
        settle_reservation(ledger, old_reservation),
        Err(ClosedReservation),
      )
      assert_eq(release_allocation(ledger, old_holding), Err(ClosedHolding))
      assert_eq(ledger_usage(ledger), before)
    }
    release_allocation(ledger, holding).unwrap()
    settle_reservation(ledger, reservation).unwrap()
    let usage = ledger_usage(ledger)
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
    previous = Some((reservation, holding))
  }
}

///|
test "live slots refuse a third concurrent reservation and return only the retired original" {
  let ledger = live_slot_test_ledger()
  let first = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let second = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let full = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(AttemptLimit))
  assert_eq(ledger_usage(ledger), full)
  settle_reservation(ledger, first).unwrap()
  let replacement = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  assert_true(first.serial != replacement.serial)
  let replaced = ledger_usage(ledger)
  assert_eq(settle_reservation(ledger, first), Err(ClosedReservation))
  assert_eq(ledger_usage(ledger), replaced)
  settle_reservation(ledger, second).unwrap()
  settle_reservation(ledger, replacement).unwrap()
}

///|
test "live slots recycle holdings while consumed transfer and work remain spent" {
  let ledger = live_slot_test_ledger()
  charge_planning(ledger, 7).unwrap()
  let reservation = reserve_attempt(ledger, 3L, 12L, 0L).unwrap()
  charge_transfer(ledger, reservation, 2L).unwrap()
  let first = retain_allocation(ledger, reservation, 4L).unwrap()
  let second = retain_allocation(ledger, reservation, 4L).unwrap()
  let full = ledger_usage(ledger)
  assert_true(retain_allocation(ledger, reservation, 1L) is Err(HoldingLimit))
  assert_eq(ledger_usage(ledger), full)
  release_allocation(ledger, first).unwrap()
  let replacement = retain_allocation(ledger, reservation, 1L).unwrap()
  assert_true(first.serial != replacement.serial)
  release_allocation(ledger, second).unwrap()
  release_allocation(ledger, replacement).unwrap()
  settle_reservation(ledger, reservation).unwrap()
  let retired = ledger_usage(ledger)
  assert_eq(retired.transferred_bytes, 2L)
  assert_eq(retired.planning_work, 7)
  assert_true(reserve_attempt(ledger, 2L, 0L, 0L) is Err(TransferLimit))
  assert_eq(charge_planning(ledger, 4), Err(PlanningLimit))
  assert_eq(ledger_usage(ledger), retired)
}

///|
test "live slots keep original inventory bounded across 10000 completed cycles" {
  let ledger = live_slot_test_ledger()
  let bootstrap = reserve_capacity(ledger, 4L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 2, 1).unwrap()
  for _ in 0..<10000 {
    let reservation = reserve_attempt(ledger, 0L, 4L, 2L).unwrap()
    let holding = retain_allocation(ledger, reservation, 4L).unwrap()
    release_allocation(ledger, holding).unwrap()
    settle_reservation(ledger, reservation).unwrap()
    let inventory = ledger.original_inventory.unwrap()
    assert_eq(inventory.reservations.length(), 0)
    assert_eq(inventory.holdings.length(), 0)
    assert_eq(inventory.delegations.length(), 0)
    assert_true(inventory.reservations.values.capacity() <= 8)
    assert_true(inventory.holdings.values.capacity() <= 8)
    assert_true(inventory.reservations.values.is_empty())
    assert_true(inventory.holdings.values.is_empty())
    assert_true(inventory.holding_counts.is_empty())
    assert_true(inventory.holding_counts.capacity() <= 8)
    assert_eq(ledger_usage(ledger).reserved_retention_bytes, 4L)
    assert_eq(ledger_usage(ledger).reserved_execution_bytes, 2L)
  }
  // Retiring live controls must not make an already used Run a fresh prefix.
  assert_false(original_ledger_prefix_available(identity))
  issue_recorded_original_ledger_descriptor(
    identity,
    original_read_test_origin(),
  ).unwrap()
  |> ignore
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "two live inventory slots support 10000 consumed attempts without resetting the same budget" {
  let ledger = create_ledger({
    ..live_slot_test_ledger().limits,
    attempts: 10000,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 4L, 2L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 2, 2, 0).unwrap() |> ignore
  for consumed in 1..<10001 {
    let reservation = reserve_attempt(ledger, 0L, 4L, 2L).unwrap()
    // Trusted Start accounting is explicit; this component starts no actual
    // VM, request or SDK Run and does not stand in for their physical ACK.
    consume_reserved_attempt(ledger, reservation).unwrap()
    let holding = retain_allocation(ledger, reservation, 4L).unwrap()
    release_allocation(ledger, holding).unwrap()
    settle_reservation(ledger, reservation).unwrap()
    assert_eq(ledger_usage(ledger).attempts, consumed)
    assert_eq(ledger_usage(ledger).reserved_attempts, 0)
    assert_eq(ledger_usage(ledger).live_reservations, 1)
    assert_eq(ledger_usage(ledger).holdings, 0)
    let inventory = ledger.original_inventory.unwrap()
    assert_true(inventory.reservations.values.capacity() <= 8)
    assert_true(inventory.holdings.values.capacity() <= 8)
    assert_eq(inventory.reservations.length(), 0)
    assert_eq(inventory.holdings.length(), 0)
  }
  let spent = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(AttemptLimit))
  assert_eq(ledger_usage(ledger), spent)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).attempts, 10000)
  assert_eq(ledger.next_attempt_serial, Some(10000))
  assert_eq(ledger.next_holding_serial, Some(10000))
}

///|
test "actual attempt consumption survives settlement while unused reservations return" {
  let ledger = live_slot_test_ledger()
  for consumed in 1..<3 {
    let reservation = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
    assert_eq(ledger_usage(ledger).reserved_attempts, 1)
    // An explicit trusted accounting notification, not dispatch or an ACK.
    consume_reserved_attempt(ledger, reservation).unwrap()
    consume_reserved_attempt(ledger, reservation).unwrap()
    assert_eq(ledger_usage(ledger).attempts, consumed)
    assert_eq(ledger_usage(ledger).reserved_attempts, 0)
    mark_transfer_uncertain(ledger, reservation, 0L).unwrap()
    settle_reservation(ledger, reservation).unwrap()
    assert_eq(ledger_usage(ledger).attempts, consumed)
    assert_eq(ledger_usage(ledger).live_reservations, 0)
  }
  let spent = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(AttemptLimit))
  assert_eq(ledger_usage(ledger), spent)
}

///|
test "child live occupation can return repeatedly without refunding consumed budgets" {
  let limits = live_slot_test_ledger().limits
  let parent = create_ledger({
    ..limits,
    attempts: 4,
    retained_bytes: 64L,
    execution_bytes: 32L,
  }).unwrap()
  let child = create_ledger(limits).unwrap()
  let delegation = reserve_execution_delegation(parent, limits, 32L, 16L).unwrap()
  for _ in 0..<10000 {
    let reservation = reserve_attempt(child, 0L, 4L, 2L).unwrap()
    report_execution_delegation(parent, delegation, ledger_usage(child)).unwrap()
    let holding = retain_allocation(child, reservation, 4L).unwrap()
    report_execution_delegation(parent, delegation, ledger_usage(child)).unwrap()
    assert_eq(ledger_usage(parent).holdings, 1)
    release_allocation(child, holding).unwrap()
    settle_reservation(child, reservation).unwrap()
    report_execution_delegation(parent, delegation, ledger_usage(child)).unwrap()
    assert_eq(ledger_usage(parent).holdings, 0)
    assert_eq(ledger_usage(parent).reserved_attempts, 1)
    assert_eq(ledger_usage(parent).live_reservations, 1)
    assert_eq(ledger_usage(parent).live_delegations, 1)
  }
  let send = reserve_attempt(child, 3L, 0L, 0L).unwrap()
  consume_reserved_attempt(child, send).unwrap()
  charge_transfer(child, send, 2L).unwrap()
  mark_transfer_uncertain(child, send, 1L).unwrap()
  settle_reservation(child, send).unwrap()
  report_execution_delegation(parent, delegation, ledger_usage(child)).unwrap()
  // Component fixture supplies confirmed domain stop, not physical VM proof.
  settle_execution_delegation(parent, delegation, Some(ledger_usage(child))).unwrap()
  let stopped = ledger_usage(parent)
  assert_eq(stopped.transferred_bytes, 2L)
  assert_eq(stopped.uncertain_transfer_bytes, 1L)
  assert_true(stopped.attempts >= 1)
  assert_eq(stopped.reserved_attempts, 0)
  assert_eq(stopped.holdings, 0)
  assert_eq(stopped.live_reservations, 0)
  assert_eq(stopped.live_delegations, 0)
  assert_eq(stopped.reserved_retention_bytes, 0L)
  assert_eq(stopped.reserved_execution_bytes, 0L)
}
