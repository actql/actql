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

///|
test "completed output returns unused retention but keeps pending scratch and consumption" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 10L, 12L).unwrap()
  charge_planning(ledger, 2).unwrap()
  charge_transfer(ledger, reservation, 3L).unwrap()
  let holding = retain_allocation(ledger, reservation, 4L).unwrap()
  settle_completed_output_reservation(
    ledger,
    reservation,
    Some(holding),
    4L,
    7L,
  ).unwrap()
  let partial = ledger_usage(ledger)
  assert_eq(partial.planning_work, 2)
  assert_eq(partial.transferred_bytes, 3L)
  assert_eq(partial.held_bytes, 4L)
  assert_eq(partial.reserved_transfer_bytes, 0L)
  assert_eq(partial.reserved_retention_bytes, 0L)
  assert_eq(partial.reserved_execution_bytes, 7L)
  assert_true(reservation_pending(reservation))
  // A new attempt can use the six unused retention bytes while scratch waits.
  let next = reserve_attempt(ledger, 0L, 6L, 0L).unwrap()
  settle_reservation(ledger, next).unwrap()
  let stable = ledger_usage(ledger)
  settle_completed_output_reservation(
    ledger,
    reservation,
    Some(holding),
    4L,
    7L,
  ).unwrap()
  assert_eq(ledger_usage(ledger), stable)
  // Pending/failed cleanup does not refund scratch. A successful confirmation
  // settles it once and leaves the accepted holding intact.
  mark_cleanup_pending(ledger, reservation).unwrap()
  assert_eq(ledger_usage(ledger), stable)
  settle_reservation(ledger, reservation).unwrap()
  let cleaned = ledger_usage(ledger)
  assert_eq(cleaned.reserved_execution_bytes, 0L)
  assert_eq(cleaned.held_bytes, 4L)
  assert_eq(cleaned.transferred_bytes, 3L)
  assert_true(settle_reservation(ledger, reservation) is Err(ClosedReservation))
  settle_completed_output_reservation(
    ledger,
    reservation,
    Some(holding),
    4L,
    7L,
  ).unwrap()
  assert_eq(ledger_usage(ledger), cleaned)
  release_allocation(ledger, holding).unwrap()
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
}

///|
test "completed output rejects foreign unconfirmed or invalid notification without mutation" {
  let ledger = create_ledger(test_limits()).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 0L, 5L, 10L).unwrap()
  let other = reserve_attempt(ledger, 0L, 4L, 0L).unwrap()
  let holding = retain_allocation(ledger, reservation, 2L).unwrap()
  let other_holding = retain_allocation(ledger, other, 2L).unwrap()
  let foreign_reservation = reserve_attempt(foreign, 0L, 2L, 1L).unwrap()
  let foreign_holding = retain_allocation(foreign, foreign_reservation, 2L).unwrap()
  let before = ledger_usage(ledger)
  let foreign_before = ledger_usage(foreign)
  assert_true(
    settle_completed_output_reservation(
      foreign,
      reservation,
      Some(holding),
      2L,
      3L,
    )
    is Err(ForeignOwner),
  )
  assert_true(
    settle_completed_output_reservation(
      ledger,
      reservation,
      Some(foreign_holding),
      2L,
      3L,
    )
    is Err(ForeignOwner),
  )
  assert_true(
    settle_completed_output_reservation(
      ledger,
      reservation,
      Some(other_holding),
      2L,
      3L,
    )
    is Err(InvalidCharge),
  )
  assert_true(
    settle_completed_output_reservation(ledger, reservation, None, 2L, 3L)
    is Err(InvalidCharge),
  )
  assert_true(
    settle_completed_output_reservation(
      ledger,
      reservation,
      Some(holding),
      3L,
      3L,
    )
    is Err(InvalidCharge),
  )
  assert_true(
    settle_completed_output_reservation(
      ledger,
      reservation,
      Some(holding),
      2L,
      -1L,
    )
    is Err(InvalidCharge),
  )
  assert_true(
    settle_completed_output_reservation(
      ledger,
      reservation,
      Some(holding),
      2L,
      11L,
    )
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(foreign), foreign_before)
  release_allocation(ledger, holding).unwrap()
  let released = ledger_usage(ledger)
  assert_true(
    settle_completed_output_reservation(
      ledger,
      reservation,
      Some(holding),
      2L,
      3L,
    )
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), released)
}

///|
test "completed empty output settles immediate scratch and rejects changed duplicates" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 5L, 8L, 4L).unwrap()
  settle_completed_output_reservation(ledger, reservation, None, 0L, 0L).unwrap()
  let settled = ledger_usage(ledger)
  assert_eq(settled.reserved_retention_bytes, 0L)
  assert_eq(settled.reserved_execution_bytes, 0L)
  assert_false(reservation_open(reservation))
  settle_completed_output_reservation(ledger, reservation, None, 0L, 0L).unwrap()
  assert_true(
    settle_completed_output_reservation(ledger, reservation, None, 0L, 1L)
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), settled)
}

///|
test "completed output preserves observed quantities and refunds undispatched quantities" {
  let ledger = create_ledger(test_limits()).unwrap()
  configure_quantities(ledger, {
    tokens: 50L,
    cost_units: 50L,
    duration_ms: 50L,
  }).unwrap()
  let first = reserve_attempt(
    ledger,
    4L,
    5L,
    6L,
    quantities=Some({ tokens: 10L, cost_units: 12L, duration_ms: 14L, }),
  ).unwrap()
  mark_quantities_uncertain(ledger, first).unwrap()
  observe_quantities(ledger, first, tokens=Some(3L)).unwrap()
  let held = retain_allocation(ledger, first, 2L).unwrap()
  let observed = quantity_usage(ledger)
  settle_completed_output_reservation(ledger, first, Some(held), 2L, 4L).unwrap()
  assert_eq(quantity_usage(ledger), observed)
  let second = reserve_attempt(
    ledger,
    0L,
    0L,
    1L,
    quantities=Some({ tokens: 5L, cost_units: 5L, duration_ms: 5L, }),
  ).unwrap()
  settle_completed_output_reservation(ledger, second, None, 0L, 1L).unwrap()
  assert_eq(quantity_usage(ledger), observed)
  let before = ledger_usage(ledger)
  assert_true(charge_transfer(ledger, first, 0L) is Err(ClosedReservation))
  assert_true(
    mark_transfer_uncertain(ledger, first, 0L) is Err(ClosedReservation),
  )
  assert_true(retain_allocation(ledger, first, 0L) is Err(ClosedReservation))
  assert_true(
    settle_completed_output_reservation(ledger, first, Some(held), 2L, 3L)
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), before)
}
