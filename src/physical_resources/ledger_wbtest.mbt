///|
fn test_limits() -> LedgerLimits {
  {
    planning_work: 10,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 12L,
    retained_bytes: 10L,
    execution_bytes: 20L,
  }
}

///|
test "unknown dispatch transfer survives cleanup and retains capacity" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 5L).unwrap()
  charge_transfer(ledger, reservation, 2L).unwrap()
  mark_transfer_uncertain(ledger, reservation, 7L).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 7L)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 0L)
  settle_reservation(ledger, reservation).unwrap()
  let usage = ledger_usage(ledger)
  assert_eq(usage.uncertain_transfer_bytes, 7L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_true(reserve_attempt(ledger, 4L, 0L, 0L) is Err(TransferLimit))
  // The remaining three bytes are independently known from the 12-byte cap.
  let remaining = reserve_attempt(ledger, 3L, 0L, 0L).unwrap()
  charge_transfer(ledger, remaining, 3L).unwrap()
  settle_reservation(ledger, remaining).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 5L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 7L)
}

///|
test "unknown transfer admission rejects without mutating usage" {
  let ledger = create_ledger(test_limits()).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 5L, 0L, 0L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    mark_transfer_uncertain(ledger, reservation, -1L) is Err(InvalidCharge),
  )
  assert_true(
    mark_transfer_uncertain(ledger, reservation, 6L) is Err(TransferLimit),
  )
  assert_true(
    mark_transfer_uncertain(foreign, reservation, 5L) is Err(ForeignOwner),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(foreign).uncertain_transfer_bytes, 0L)
  mark_transfer_uncertain(ledger, reservation, 5L).unwrap()
  let marked = ledger_usage(ledger)
  assert_true(
    mark_transfer_uncertain(ledger, reservation, 1L) is Err(TransferLimit),
  )
  assert_eq(ledger_usage(ledger), marked)
  settle_reservation(ledger, reservation).unwrap()
  let settled = ledger_usage(ledger)
  assert_true(
    mark_transfer_uncertain(ledger, reservation, 0L) is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), settled)
}

///|
test "opaque resource readers distinguish ownership from current availability" {
  let ledger = create_ledger(test_limits()).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  assert_eq(ledger_limits(ledger), test_limits())
  let reservation = reserve_attempt(ledger, 0L, 6L, 0L).unwrap()
  assert_true(reservation_open(reservation))
  let holding = retain_allocation(ledger, reservation, 6L).unwrap()
  assert_true(holding_belongs_to(ledger, holding))
  assert_true(holding_available(ledger, holding))
  assert_false(holding_belongs_to(foreign, holding))
  assert_false(holding_available(foreign, holding))
  settle_reservation(ledger, reservation).unwrap()
  assert_false(reservation_open(reservation))
  assert_true(holding_available(ledger, holding))
  release_allocation(ledger, holding).unwrap()
  assert_true(holding_belongs_to(ledger, holding))
  assert_false(holding_available(ledger, holding))
}

///|
test "sunk transfers survive settlement replanning failure and cancellation" {
  let ledger = create_ledger(test_limits()).unwrap()
  let first = reserve_attempt(ledger, 9L, 10L, 20L).unwrap()
  charge_transfer(ledger, first, 9L).unwrap()
  let held = retain_allocation(ledger, first, 6L).unwrap()
  mark_cleanup_pending(ledger, first).unwrap()
  assert_true(reservation_pending(first))
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_true(reserve_attempt(ledger, 0L, 0L, 1L) is Err(ExecutionLimit))
  settle_reservation(ledger, first).unwrap()
  assert_false(reservation_pending(first))
  assert_eq(ledger_usage(ledger).transferred_bytes, 9L)
  assert_eq(ledger_usage(ledger).held_bytes, 6L)
  assert_true(reserve_attempt(ledger, 4L, 0L, 0L) is Err(TransferLimit))
  let second = reserve_attempt(ledger, 3L, 4L, 20L).unwrap()
  assert_eq(reservation_serial(second), 1)
  let before = ledger_usage(ledger)
  assert_true(charge_transfer(ledger, second, 4L) is Err(TransferLimit))
  assert_eq(ledger_usage(ledger), before)
  charge_transfer(ledger, second, 3L).unwrap()
  settle_reservation(ledger, second).unwrap()
  release_allocation(ledger, held).unwrap()
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  assert_eq(ledger_usage(ledger).transferred_bytes, 12L)
  assert_eq(ledger_usage(ledger).peak_retention_bytes, 10L)
  assert_true(reserve_attempt(ledger, 1L, 0L, 0L) is Err(TransferLimit))
  assert_true(charge_transfer(ledger, first, 0L) is Err(ClosedReservation))
  assert_true(settle_reservation(ledger, first) is Err(ClosedReservation))
}

///|
test "allocation identity not content equality determines physical holding" {
  let ledger = create_ledger(test_limits()).unwrap()
  let first = reserve_attempt(ledger, 0L, 6L, 0L).unwrap()
  let held = retain_allocation(ledger, first, 6L).unwrap()
  let shared = held
  assert_true(physical_equal(shared, held))
  assert_eq(ledger_usage(ledger).held_bytes, 6L)
  assert_true(reserve_attempt(ledger, 0L, 6L, 0L) is Err(RetentionLimit))
  let another = reserve_attempt(ledger, 0L, 4L, 0L).unwrap()
  let copy = retain_allocation(ledger, another, 4L).unwrap()
  assert_false(physical_equal(copy, held))
  assert_eq(holding_serial(copy), 1)
  assert_eq(ledger_usage(ledger).held_bytes, 10L)
  let foreign = create_ledger(test_limits()).unwrap()
  assert_true(release_allocation(foreign, held) is Err(ForeignOwner))
  assert_true(charge_transfer(foreign, first, 0L) is Err(ForeignOwner))
  release_allocation(ledger, shared).unwrap()
  assert_true(release_allocation(ledger, held) is Err(ClosedHolding))
  assert_eq(ledger_usage(ledger).held_bytes, 4L)
}

///|
test "planning and record limits are cumulative and checked before mutation" {
  let ledger = create_ledger({ ..test_limits(), attempts: 1, holdings: 1, }).unwrap()
  charge_planning(ledger, 10).unwrap()
  assert_true(charge_planning(ledger, 1) is Err(PlanningLimit))
  assert_true(charge_planning(ledger, -1) is Err(InvalidCharge))
  assert_true(reserve_attempt(ledger, -1L, 0L, 0L) is Err(InvalidCharge))
  let r = reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let h = retain_allocation(ledger, r, 5L).unwrap()
  release_allocation(ledger, h).unwrap()
  assert_true(retain_allocation(ledger, r, 0L) is Err(HoldingLimit))
  settle_reservation(ledger, r).unwrap()
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(AttemptLimit))
  assert_eq(ledger_usage(ledger).planning_work, 10)
}

///|
test "reservation arithmetic rejects overflow without losing charges" {
  let ledger = create_ledger({
    ..test_limits(),
    transfer_bytes: 9223372036854775807L,
    retained_bytes: 9223372036854775807L,
    execution_bytes: 9223372036854775807L,
  }).unwrap()
  let r = reserve_attempt(
    ledger, 9223372036854775807L, 9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(reserve_attempt(ledger, 1L, 0L, 0L) is Err(TransferLimit))
  assert_true(reserve_attempt(ledger, 0L, 1L, 0L) is Err(RetentionLimit))
  assert_true(reserve_attempt(ledger, 0L, 0L, 1L) is Err(ExecutionLimit))
  charge_transfer(ledger, r, 9223372036854775807L).unwrap()
  settle_reservation(ledger, r).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 9223372036854775807L)
}
