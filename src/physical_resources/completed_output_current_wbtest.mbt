///|
fn completed_current_ledger() -> Ledger {
  create_ledger({
    planning_work: 8,
    attempts: 2,
    holdings: 2,
    transfer_bytes: 16L,
    retained_bytes: 16L,
    execution_bytes: 16L,
  }).unwrap()
}

///|
fn completed_current_callback(
  ledger : Ledger,
  reservation : Reservation,
  remaining : Int64,
) -> Ref[LedgerUsage?] {
  let armed = Ref(true)
  let observed = Ref(None)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        settle_completed_output_reservation(
          ledger,
          reservation,
          None,
          0L,
          remaining,
        ).unwrap()
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
    current_window: None,
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  observed
}

///|
test "completed notification current callback cannot replace the first scratch notification" {
  let ledger = completed_current_ledger()
  let reservation = reserve_attempt(ledger, 3L, 4L, 8L).unwrap()
  consume_reserved_attempt(ledger, reservation).unwrap()
  let observed = completed_current_callback(ledger, reservation, 5L)
  assert_eq(
    settle_completed_output_reservation(ledger, reservation, None, 0L, 0L),
    Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), observed.val.unwrap())
  assert_eq(reservation.completed_output, Some((None, 0L, 5L)))
  assert_eq(reservation.execution, 5L)
  assert_true(reservation_pending(reservation))
  assert_eq(completed_output_attempt_sequence(ledger, reservation), 1)
  assert_eq(
    completed_output_attempt_sequence(completed_current_ledger(), reservation),
    0,
  )
  assert_eq(ledger_usage(ledger).attempts, 1)
  settle_reservation(ledger, reservation).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 1)
}

///|
test "completed notification current callback preserves identical closed completion idempotence" {
  let ledger = completed_current_ledger()
  let reservation = reserve_attempt(ledger, 3L, 4L, 8L).unwrap()
  let observed = completed_current_callback(ledger, reservation, 0L)
  assert_eq(
    settle_completed_output_reservation(ledger, reservation, None, 0L, 0L),
    Ok(()),
  )
  assert_eq(ledger_usage(ledger), observed.val.unwrap())
  assert_eq(reservation.completed_output, Some((None, 0L, 0L)))
  assert_false(reservation.open)
  assert_eq(ledger_usage(ledger).live_reservations, 0)
  assert_eq(ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(completed_output_attempt_sequence(ledger, reservation), 0)
}

///|
test "completed attempts preserve first-use order across reversed reservation order and retries" {
  let ledger = completed_current_ledger()
  let first_reserved = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let first_used = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  assert_eq(
    (reservation_serial(first_reserved), reservation_serial(first_used)),
    (0, 1),
  )
  assert_eq(
    consume_reserved_attempt(completed_current_ledger(), first_used),
    Err(ForeignOwner),
  )
  consume_reserved_attempt(ledger, first_used).unwrap()
  consume_reserved_attempt(ledger, first_reserved).unwrap()
  consume_reserved_attempt(ledger, first_used).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 2)
  assert_eq(completed_output_attempt_sequence(ledger, first_used), 0)
  settle_completed_output_reservation(ledger, first_used, None, 0L, 0L).unwrap()
  settle_completed_output_reservation(ledger, first_reserved, None, 0L, 0L).unwrap()
  assert_eq(completed_output_attempt_sequence(ledger, first_used), 1)
  assert_eq(completed_output_attempt_sequence(ledger, first_reserved), 2)
  assert_eq(
    consume_reserved_attempt(ledger, first_used),
    Err(ClosedReservation),
  )
  assert_eq(completed_output_attempt_sequence(ledger, first_used), 1)
  assert_eq(ledger_usage(ledger).live_reservations, 0)
}
