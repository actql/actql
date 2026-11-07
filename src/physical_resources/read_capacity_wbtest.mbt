///|
fn read_capacity_fixture(retained : Int64, execution : Int64) -> Ledger {
  create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
}

///|
test "original byte coverage checks both dimensions without changing custody" {
  let ledger = read_capacity_fixture(17L, 13L)
  let token = reserve_capacity(ledger, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  assert_true(capacity_reservation_covers(ledger, token, 7L, 5L))
  assert_true(capacity_reservation_covers(ledger, token, 6L, 4L))
  assert_true(capacity_reservation_covers(ledger, token, 0L, 0L))
  assert_false(capacity_reservation_covers(ledger, token, 8L, 5L))
  assert_false(capacity_reservation_covers(ledger, token, 7L, 6L))
  assert_false(capacity_reservation_covers(ledger, token, -1L, 0L))
  assert_false(capacity_reservation_covers(ledger, token, 0L, -1L))
  assert_false(
    capacity_reservation_covers(ledger, token, 9223372036854775807L, 0L),
  )
  // Spare Ledger capacity is not allowance held by this token.
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  // The older exact-match check is still exact.
  assert_true(capacity_reservation_matches(ledger, token, 7L, 5L))
  assert_false(capacity_reservation_matches(ledger, token, 6L, 4L))
  settle_capacity(ledger, token).unwrap()
  assert_false(capacity_reservation_covers(ledger, token, 0L, 0L))
}

///|
test "original byte coverage rejects foreign pending and nonbyte tokens" {
  let ledger = read_capacity_fixture(7L, 5L)
  let foreign = read_capacity_fixture(7L, 5L)
  let token = reserve_capacity(ledger, 7L, 5L).unwrap()
  assert_false(capacity_reservation_covers(foreign, token, 7L, 5L))
  mark_cleanup_pending(ledger, token.reservation).unwrap()
  assert_true(capacity_reservation_open(token))
  assert_false(capacity_reservation_covers(ledger, token, 0L, 0L))
  settle_execution_reservation(
    ledger,
    token.reservation,
    remaining_execution=5L,
  ).unwrap()
  assert_true(capacity_reservation_covers(ledger, token, 7L, 5L))
  settle_capacity(ledger, token).unwrap()

  // White-box construction cannot turn a send token into byte-only custody.
  let send = reserve_attempt(ledger, 1L, 7L, 5L).unwrap()
  let forged : CapacityReservation = { reservation: send, }
  assert_false(capacity_reservation_covers(ledger, forged, 7L, 5L))
  settle_reservation(ledger, send).unwrap()
}

///|
test "original byte coverage does not adopt reserved or uncertain quantities" {
  let ledger = read_capacity_fixture(7L, 5L)
  configure_quantities(ledger, {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }).unwrap()
  let send = reserve_attempt(
    ledger,
    0L,
    7L,
    5L,
    quantities=Some({ tokens: 1L, cost_units: 2L, duration_ms: 3L, }),
  ).unwrap()
  let forged : CapacityReservation = { reservation: send, }
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  assert_false(capacity_reservation_covers(ledger, forged, 0L, 0L))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(quantity_usage(ledger), quantities)
  mark_quantities_uncertain(ledger, send).unwrap()
  let uncertain = quantity_usage(ledger)
  assert_false(capacity_reservation_covers(ledger, forged, 0L, 0L))
  assert_eq(ledger_usage(ledger), {
    ..before,
    attempts: 1,
    reserved_attempts: 0,
  })
  assert_eq(quantity_usage(ledger), uncertain)
  settle_reservation(ledger, send).unwrap()
  assert_eq(quantity_usage(ledger).uncertain, uncertain.uncertain)
}

///|
test "read capacity admits exact bytes without send or quantity authority" {
  let ledger = read_capacity_fixture(7L, 5L)
  configure_quantities(ledger, {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }).unwrap()
  let quantities = quantity_usage(ledger)
  let read = reserve_capacity(ledger, 7L, 5L).unwrap()
  let usage = ledger_usage(ledger)
  assert_eq(usage.attempts, 0)
  assert_eq(usage.holdings, 0)
  assert_eq(usage.transferred_bytes, 0L)
  assert_eq(usage.uncertain_transfer_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 7L)
  assert_eq(usage.reserved_execution_bytes, 5L)
  assert_eq(usage.peak_retention_bytes, 7L)
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(capacity_reservation_open(read))
  // The only public handle is CapacityReservation, not Reservation. Even
  // within this white-box test, its zero envelopes grant no physical usage.
  assert_true(
    charge_transfer(ledger, read.reservation, 1L) is Err(TransferLimit),
  )
  assert_true(
    mark_quantities_uncertain(ledger, read.reservation) is Err(InvalidCharge),
  )
  assert_eq(ledger_usage(ledger), usage)
  assert_eq(quantity_usage(ledger), quantities)
  settle_capacity(ledger, read).unwrap()
  assert_true(!capacity_reservation_open(read))
  assert_true(settle_capacity(ledger, read) is Err(ClosedReservation))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(quantity_usage(ledger), quantities)
}

///|
test "read capacity one-short and invalid admission are atomic" {
  for (retained, execution) in [(6L, 5L), (7L, 4L)] {
    let ledger = read_capacity_fixture(retained, execution)
    let before = ledger_usage(ledger)
    let result = reserve_capacity(ledger, 7L, 5L)
    assert_true(
      if retained == 6L {
        result is Err(RetentionLimit)
      } else {
        result is Err(ExecutionLimit)
      },
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, Some(-1))
    configure_quantities(ledger, zero_quantities()).unwrap()
  }
  let ledger = read_capacity_fixture(7L, 5L)
  let before = ledger_usage(ledger)
  for (retained, execution) in [(-1L, 0L), (0L, -1L)] {
    assert_true(
      reserve_capacity(ledger, retained, execution) is Err(InvalidCharge),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, Some(-1))
  }
  let foreign = read_capacity_fixture(7L, 5L)
  let read = reserve_capacity(ledger, 7L, 5L).unwrap()
  assert_true(settle_capacity(foreign, read) is Err(ForeignOwner))
  assert_true(capacity_reservation_open(read))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 7L)
  settle_capacity(ledger, read).unwrap()
}

///|
test "read capacity closes quantity configuration even after settlement" {
  let ledger = read_capacity_fixture(7L, 5L)
  let read = reserve_capacity(ledger, 0L, 0L).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_true(
    configure_quantities(ledger, zero_quantities()) is Err(InvalidCharge),
  )
  settle_capacity(ledger, read).unwrap()
  assert_true(
    configure_quantities(ledger, zero_quantities()) is Err(InvalidCharge),
  )
  // Normal send identity/capacity are not replenished by the read lifecycle.
  let send = reserve_attempt(ledger, 11L, 7L, 5L).unwrap()
  assert_eq(reservation_serial(send), 0)
  charge_transfer(ledger, send, 11L).unwrap()
  settle_reservation(ledger, send).unwrap()
  assert_true(reserve_attempt(ledger, 1L, 0L, 0L) is Err(TransferLimit))
  assert_eq(ledger_usage(ledger).transferred_bytes, 11L)
}

///|
test "read capacity identities reject crossed equal-byte holdings after settlement" {
  let ledger = read_capacity_fixture(21L, 0L)
  let read1 = reserve_capacity(ledger, 7L, 0L).unwrap()
  let read2 = reserve_capacity(ledger, 7L, 0L).unwrap()
  let send = reserve_attempt(ledger, 0L, 7L, 0L).unwrap()
  assert_eq(reservation_serial(read1.reservation), -1)
  assert_eq(reservation_serial(read2.reservation), -2)
  assert_eq(reservation_serial(send), 0)
  // This internal construction exercises the existing holding matcher. No
  // public API converts read custody to a send/holding reservation.
  let held1 = retain_allocation(ledger, read1.reservation, 7L).unwrap()
  let held2 = retain_allocation(ledger, read2.reservation, 7L).unwrap()
  let held_send = retain_allocation(ledger, send, 7L).unwrap()
  for
    (reservation, crossed) in [
      (read1.reservation, held2),
      (read2.reservation, held_send),
      (send, held1),
    ] {
    assert_true(
      settle_completed_output_reservation(
        ledger,
        reservation,
        Some(crossed),
        7L,
        0L,
      )
      is Err(InvalidCharge),
    )
  }
  settle_completed_output_reservation(
    ledger,
    read1.reservation,
    Some(held1),
    7L,
    0L,
  ).unwrap()
  settle_completed_output_reservation(
    ledger,
    read2.reservation,
    Some(held2),
    7L,
    0L,
  ).unwrap()
  settle_completed_output_reservation(ledger, send, Some(held_send), 7L, 0L).unwrap()
  assert_true(
    settle_completed_output_reservation(
      ledger,
      read1.reservation,
      Some(held2),
      7L,
      0L,
    )
    is Err(InvalidCharge),
  )
  // Releasing byte capacity does not recycle either identity domain.
  release_allocation(ledger, held1).unwrap()
  release_allocation(ledger, held2).unwrap()
  release_allocation(ledger, held_send).unwrap()
  let next_read = reserve_capacity(ledger, 7L, 0L).unwrap()
  let next_send = reserve_attempt(ledger, 0L, 7L, 0L).unwrap()
  assert_eq(reservation_serial(next_read.reservation), -3)
  assert_eq(reservation_serial(next_send), 1)
  settle_capacity(ledger, next_read).unwrap()
  settle_reservation(ledger, next_send).unwrap()
}

///|
test "read capacity exhaustion and maximal byte counters never wrap" {
  let ledger = read_capacity_fixture(9223372036854775807L, 9223372036854775807L)
  ledger.next_capacity_serial = Some(-2147483648)
  let final_read = reserve_capacity(
    ledger, 9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_eq(reservation_serial(final_read.reservation), -2147483648)
  assert_true(ledger.next_capacity_serial is None)
  let before = ledger_usage(ledger)
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(InvalidCharge))
  assert_eq(ledger_usage(ledger), before)
  settle_capacity(ledger, final_read).unwrap()
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(InvalidCharge))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "read capacity cleanup retains custody without settling unknown send usage" {
  let ledger = read_capacity_fixture(14L, 5L)
  configure_quantities(ledger, {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }).unwrap()
  let original = reserve_attempt(
    ledger,
    11L,
    7L,
    0L,
    quantities=Some({ tokens: 13L, cost_units: 17L, duration_ms: 19L, }),
  ).unwrap()
  mark_transfer_uncertain(ledger, original, 11L).unwrap()
  mark_quantities_uncertain(ledger, original).unwrap()
  let read = reserve_capacity(ledger, 7L, 5L).unwrap()
  let before = ledger_usage(ledger)
  let quantities = quantity_usage(ledger)
  // A pending/failed physical cleanup does not call the trusted settlement
  // acknowledgement. The same owner keeps this exact read reservation.
  let mut cleanup_attempts = 0
  let cleanup = () => {
    cleanup_attempts += 1
    if cleanup_attempts == 1 {
      Err(InvalidCharge)
    } else {
      settle_capacity(ledger, read)
    }
  }
  assert_true(cleanup() is Err(InvalidCharge))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(capacity_reservation_open(read))
  cleanup().unwrap()
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 7L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 11L)
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(settle_capacity(ledger, read) is Err(ClosedReservation))
  settle_reservation(ledger, original).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 11L)
  assert_eq(quantity_usage(ledger), quantities)
}

///|
test "byte-only growth keeps its original identity and cannot mint work" {
  let ledger = read_capacity_fixture(17L, 13L)
  let foreign = read_capacity_fixture(17L, 13L)
  let token = reserve_capacity(ledger, 4L, 6L).unwrap()
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let send_serial = ledger.next_attempt_serial
  let quantities = quantity_usage(ledger)
  grow_capacity_reservation(ledger, token, 10L, 12L).unwrap()
  let grown = ledger_usage(ledger)
  assert_eq(grown, {
    ..before,
    reserved_retention_bytes: 10L,
    reserved_execution_bytes: 12L,
    peak_retention_bytes: 10L,
  })
  assert_true(capacity_reservation_matches(ledger, token, 10L, 12L))
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(ledger.next_attempt_serial, send_serial)
  assert_eq(quantity_usage(ledger), quantities)
  assert_true(
    grow_capacity_reservation(foreign, token, 10L, 12L) is Err(ForeignOwner),
  )
  assert_true(
    grow_capacity_reservation(ledger, token, 9L, 12L) is Err(InvalidCharge),
  )
  assert_true(
    grow_capacity_reservation(ledger, token, 10L, 11L) is Err(InvalidCharge),
  )
  assert_true(
    grow_capacity_reservation(ledger, token, 18L, 12L) is Err(RetentionLimit),
  )
  assert_true(
    grow_capacity_reservation(ledger, token, 10L, 14L) is Err(ExecutionLimit),
  )
  assert_eq(ledger_usage(ledger), grown)
  assert_eq(quantity_usage(ledger), quantities)
  assert_eq(ledger.next_capacity_serial, serial)
  settle_capacity(ledger, token).unwrap()
  let closed = ledger_usage(ledger)
  assert_true(
    grow_capacity_reservation(ledger, token, 10L, 12L) is Err(ClosedReservation),
  )
  assert_eq(ledger_usage(ledger), closed)
  assert_eq(closed.attempts, 0)
  assert_eq(closed.transferred_bytes, 0L)
  assert_eq(closed.live_reservations, 0)
}

///|
test "byte-only growth observes original current once and rejects its reentrant close" {
  let ledger = read_capacity_fixture(17L, 13L)
  let token = reserve_capacity(ledger, 4L, 6L).unwrap()
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      // The Resource owner, rather than the Native caller, fences this
      // synchronous callback before changing the original byte reservation.
      settle_reservation_current(ledger, token.reservation).unwrap()
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
    grow_capacity_reservation(ledger, token, 10L, 12L) is Err(ClosedReservation),
  )
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}
