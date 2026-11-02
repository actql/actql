///|
// Existing primitive effects, not an authorization to retire a Source or a
// claim that native stop alone completes its other obligations.
test "execution settlement preserves spent history but also clears transfer and cleanup pending" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 15L).unwrap()
  charge_transfer(ledger, reservation, 2L).unwrap()
  mark_transfer_uncertain(ledger, reservation, 2L).unwrap()
  let holding = retain_allocation(ledger, reservation, 2L).unwrap()
  mark_cleanup_pending(ledger, reservation).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(before.reserved_transfer_bytes, 5L)
  assert_true(reservation_pending(reservation))
  assert_eq(
    reservation_capacity_amounts(ledger, reservation).unwrap(),
    (2L, 15L),
  )
  assert_true(
    settle_execution_reservation(ledger, reservation, remaining_execution=16L)
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), before)
  settle_execution_reservation(ledger, reservation, remaining_execution=7L).unwrap()
  assert_eq(ledger_usage(ledger), {
    ..before,
    reserved_transfer_bytes: 0L,
    reserved_execution_bytes: 7L,
  })
  assert_false(reservation_pending(reservation))
  assert_true(reservation_open(reservation))
  assert_eq(
    reservation_capacity_amounts(ledger, reservation).unwrap(),
    (2L, 7L),
  )
  // Remaining transfer/cleanup changed; this was NOT a scratch-only operation.
  // Held output and consumed/uncertain history remain independently owned.
  settle_reservation(ledger, reservation).unwrap()
  assert_eq(ledger_usage(ledger).held_bytes, 2L)
  release_allocation(ledger, holding).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 2L)
  assert_eq(ledger_usage(ledger).attempts, before.attempts)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
// Unconnected test-only candidate. No production API or Source caller uses
// this function. Domain retirement proof remains an independent obligation.
fn reader_candidate_return_execution_workspace(
  ledger : Ledger,
  reservation : Reservation,
  bytes : Int64,
) -> Result[Unit, LedgerIssue] {
  match reservation_check(ledger, reservation) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // Currentness may replace an imported owner. Inspect its current fixed
  // policy after that SAME callback; this adds no second callback or issuer.
  if imported_child_fixed_capacity(ledger, reservation) {
    return Err(ChildFundingUnavailable)
  }
  if bytes < 0L || bytes > reservation.execution {
    return Err(InvalidCharge)
  }
  ledger.usage = {
    ..ledger.usage,
    reserved_execution_bytes: ledger.usage.reserved_execution_bytes - bytes,
  }
  reservation.execution = reservation.execution - bytes
  Ok(())
}

///|
test "candidate byte-only return preserves all other original usage debt and cleanup fields" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 15L).unwrap()
  charge_transfer(ledger, reservation, 2L).unwrap()
  mark_transfer_uncertain(ledger, reservation, 2L).unwrap()
  let holding = retain_allocation(ledger, reservation, 2L).unwrap()
  mark_cleanup_pending(ledger, reservation).unwrap()
  let before = ledger_usage(ledger)
  let quantity_before = quantity_usage(ledger)
  reader_candidate_return_execution_workspace(ledger, reservation, 8L).unwrap()
  assert_eq(ledger_usage(ledger), { ..before, reserved_execution_bytes: 7L, })
  assert_eq(quantity_usage(ledger), quantity_before)
  assert_true(reservation_pending(reservation))
  assert_true(reservation_open(reservation))
  assert_eq(
    reservation_capacity_amounts(ledger, reservation).unwrap(),
    (2L, 7L),
  )
  assert_eq(reservation.transfer, 5L)
  let after = ledger_usage(ledger)
  reader_candidate_return_execution_workspace(ledger, reservation, 0L).unwrap()
  assert_eq(ledger_usage(ledger), after)
  settle_reservation(ledger, reservation).unwrap()
  release_allocation(ledger, holding).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 2L)
}

///|
test "candidate byte-only return refuses foreign negative excessive and closed originals without credit" {
  let ledger = create_ledger(test_limits()).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 15L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    reader_candidate_return_execution_workspace(foreign, reservation, 1L)
    is Err(ForeignOwner),
  )
  for amount in [-1L, 16L] {
    assert_true(
      reader_candidate_return_execution_workspace(ledger, reservation, amount)
      is Err(InvalidCharge),
    )
    assert_eq(ledger_usage(ledger), before)
  }
  settle_reservation(ledger, reservation).unwrap()
  let closed = ledger_usage(ledger)
  assert_true(
    reader_candidate_return_execution_workspace(ledger, reservation, 1L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), closed)
}

///|
test "candidate byte-only return rechecks same reservation after generic current reentry closes it" {
  let ledger = create_ledger(test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 9L, 4L, 15L).unwrap()
  let armed = Ref(true)
  let observed : Ref[LedgerUsage?] = Ref(None)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        settle_reservation(ledger, reservation).unwrap()
        observed.val = Some(ledger_usage(ledger))
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
  })
  assert_true(
    reader_candidate_return_execution_workspace(ledger, reservation, 8L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), observed.val.unwrap())
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}
