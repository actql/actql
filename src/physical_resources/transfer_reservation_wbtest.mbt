///|
test "next transfer unit preserves one attempt and cumulative received uncertain and competing debt" {
  let ledger = create_ledger({ ..test_limits(), transfer_bytes: 32768L, }).unwrap()
  let token = reserve_attempt(ledger, 0L, 1L, 2L).unwrap()
  let serial = token.serial
  let other = reserve_attempt(ledger, 1000L, 0L, 0L).unwrap()
  let next = ledger.next_attempt_serial
  // Only this original's transfer allowance changes, not quantities or R/E.
  let baseline = ledger_usage(ledger)
  for _ in 0..<5 {
    ensure_transfer_reservation_capacity(ledger, token, 8192L).unwrap()
    let funded = ledger_usage(ledger)
    ensure_transfer_reservation_capacity(ledger, token, 8192L).unwrap()
    assert_eq(ledger_usage(ledger), funded)
    charge_transfer(ledger, token, 1000L).unwrap()
  }
  assert_eq(token.serial, serial)
  assert_eq(ledger.next_attempt_serial, next)
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).transferred_bytes, 5000L)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 8192L)
  assert_eq(
    ledger_usage(ledger).reserved_retention_bytes,
    baseline.reserved_retention_bytes,
  )
  assert_eq(
    ledger_usage(ledger).reserved_execution_bytes,
    baseline.reserved_execution_bytes,
  )
  mark_transfer_uncertain(ledger, token, 2000L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, 24769L)
    is Err(TransferLimit),
  )
  assert_eq(ledger_usage(ledger), before)
  ensure_transfer_reservation_capacity(ledger, token, 24768L).unwrap()
  charge_transfer(ledger, token, 24768L).unwrap()
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, 1L)
    is Err(TransferLimit),
  )
  settle_reservation(ledger, token).unwrap()
  settle_reservation(ledger, other).unwrap()
  let closed = ledger_usage(ledger)
  assert_eq(closed.transferred_bytes, 29768L)
  assert_eq(closed.uncertain_transfer_bytes, 2000L)
  assert_eq(closed.reserved_transfer_bytes, 0L)
  assert_eq(closed.attempts, 1)
}

///|
test "next transfer unit rejects foreign pending and closed reservations" {
  let ledger = create_ledger(test_limits()).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  let token = reserve_attempt(ledger, 0L, 1L, 2L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(
    ensure_transfer_reservation_capacity(foreign, token, 1L)
    is Err(ForeignOwner),
  )
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, -1L)
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), before)
  mark_cleanup_pending(ledger, token).unwrap()
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, 1L)
    is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 0L)
  settle_reservation(ledger, token).unwrap()
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, 1L)
    is Err(ClosedReservation),
  )
}

///|
test "next transfer unit rechecks original current before mutating the same reservation" {
  let ledger = create_ledger(test_limits()).unwrap()
  let token = reserve_attempt(ledger, 0L, 1L, 2L).unwrap()
  let armed = Ref(true)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        settle_reservation(ledger, token).unwrap()
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
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, 8L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 0)
}

///|
test "next transfer refuses stopped current even with a funded remainder but preserves post-use accounting" {
  let ledger = create_ledger(test_limits()).unwrap()
  let token = reserve_attempt(ledger, 8L, 1L, 2L).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => 1,
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
  let before = ledger_usage(ledger)
  assert_true(
    ensure_transfer_reservation_capacity(ledger, token, 8L)
    is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), before)
  charge_transfer(ledger, token, 2L).unwrap()
  mark_transfer_uncertain(ledger, token, 3L).unwrap()
  settle_reservation(ledger, token).unwrap()
  assert_eq(ledger_usage(ledger).transferred_bytes, 2L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 3L)
  assert_eq(ledger_usage(ledger).reserved_transfer_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 1)
}

///|
test "measured transfer settles once on its entered reservation and keeps prior uncertainty" {
  let ledger = create_ledger({ ..test_limits(), transfer_bytes: 16L, }).unwrap()
  let foreign = create_ledger(test_limits()).unwrap()
  let prior = reserve_attempt(ledger, 4L, 0L, 0L).unwrap()
  mark_transfer_uncertain(ledger, prior, 4L).unwrap()
  settle_reservation(ledger, prior).unwrap()
  let pending = reserve_attempt(ledger, 12L, 0L, 0L).unwrap()
  assert_eq(settle_entered_transfer(ledger, pending, 12L, Some(5L)), Ok(false))
  consume_reserved_attempt(ledger, pending).unwrap()
  let reserved = ledger_usage(ledger)
  assert_eq(reserved.reserved_transfer_bytes, 12L)
  assert_eq(reserved.uncertain_transfer_bytes, 4L)
  assert_true(reserve_attempt(ledger, 1L, 0L, 0L) is Err(TransferLimit))
  assert_eq(
    settle_entered_transfer(foreign, pending, 12L, Some(5L)),
    Err(ForeignOwner),
  )
  assert_eq(
    settle_entered_transfer(ledger, pending, 12L, Some(-1L)),
    Err(InvalidCharge),
  )
  assert_eq(
    settle_entered_transfer(ledger, pending, 12L, Some(13L)),
    Err(InvalidCharge),
  )
  assert_eq(
    settle_entered_transfer(ledger, pending, 11L, Some(5L)),
    Err(TransferLimit),
  )
  assert_eq(ledger_usage(ledger), reserved)
  assert_eq(settle_entered_transfer(ledger, pending, 12L, Some(5L)), Ok(true))
  assert_eq(settle_entered_transfer(ledger, pending, 12L, Some(3L)), Ok(false))
  assert_eq(settle_entered_transfer(ledger, pending, 12L, None), Ok(false))
  settle_reservation(ledger, pending).unwrap()
  let missing = reserve_attempt(ledger, 7L, 0L, 0L).unwrap()
  consume_reserved_attempt(ledger, missing).unwrap()
  assert_eq(settle_entered_transfer(ledger, missing, 7L, None), Ok(true))
  assert_eq(settle_entered_transfer(ledger, missing, 7L, Some(2L)), Ok(false))
  settle_reservation(ledger, missing).unwrap()
  let usage = ledger_usage(ledger)
  assert_eq(usage.attempts, 3)
  assert_eq(usage.transferred_bytes, 5L)
  assert_eq(usage.uncertain_transfer_bytes, 11L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
}
