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
