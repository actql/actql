///|
test "listing supplementary declaration checks each overlap addition without granting capacity" {
  // Independent accounting fixture units, not a selected Node layout or a
  // production physical profile. Construction changes no Ledger usage.
  // Original binding H1/R2/W1 is 16 + 2*8 + 8 = 40 tariff bytes.
  let declared = @execution.execution_capacity(7L, 9L).unwrap()
  assert_eq(
    row_listing_capacity_sum(11L, 13L, 5L, Some(declared)).unwrap(),
    (58L, 67L),
  )
  assert_true(
    row_listing_capacity_sum(11L, 13L, 5L, None) is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(
      11L,
      13L,
      5L,
      @execution.execution_capacity(0L, 0L),
    )
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(-1L, 13L, 5L, Some(declared))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(11L, -1L, 5L, Some(declared))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(11L, 13L, -1L, Some(declared))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(9223372036854775801L, 13L, 5L, Some(declared))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(11L, 9223372036854775799L, 0L, Some(declared))
    is Err(Physical(InvalidLimits)),
  )
  assert_true(
    row_listing_capacity_sum(11L, 9223372036854775798L, 1L, Some(declared))
    is Err(Physical(InvalidLimits)),
  )
}

///|
fn listing_capacity_ledger(
  retained : Int64,
  execution : Int64,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
}

///|
test "listing overlap exact fit and either one short use the same Source reservation" {
  let declaration = @execution.execution_capacity(7L, 9L).unwrap()
  let (retained, execution) = row_listing_capacity_sum(
    11L,
    13L,
    5L,
    Some(declaration),
  ).unwrap()
  assert_eq((retained, execution), (58L, 67L))
  for shortage in 0..<3 {
    let ledger = listing_capacity_ledger(
      58L - (if shortage == 1 { 1L } else { 0L }),
      67L - (if shortage == 2 { 1L } else { 0L }),
    )
    let before = @resources.ledger_usage(ledger)
    let reserved = @resources.reserve_attempt(ledger, 0L, retained, execution)
    if shortage == 0 {
      let reservation = reserved.unwrap()
      let usage = @resources.ledger_usage(ledger)
      assert_eq(usage.attempts, 0)
      assert_eq(usage.reserved_attempts, 1)
      assert_eq(usage.reserved_retention_bytes, 58L)
      assert_eq(usage.reserved_execution_bytes, 67L)
      @resources.settle_reservation(ledger, reservation).unwrap()
      assert_eq(@resources.ledger_usage(ledger).attempts, 0)
      assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
    } else {
      assert_true(
        if shortage == 1 {
          reserved is Err(@resources.RetentionLimit)
        } else {
          reserved is Err(@resources.ExecutionLimit)
        },
      )
      assert_eq(@resources.ledger_usage(ledger), before)
    }
  }
}

///|
test "listing capture keeps report and encoding overlap through pending cleanup" {
  let ledger = listing_capacity_ledger(18L, 27L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 18L, 27L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 6L).unwrap()
  let physical : RowPhysical = {
    ledger,
    reservation,
    execution_scratch: 5L,
    provider_capacity: None,
    holding: Some(holding),
    dag: None,
    cleanup_confirmed: None,
  }
  let before = @resources.ledger_usage(ledger)
  settle_row_capture_capacity(true, physical).unwrap()
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(before.held_bytes, 6L)
  assert_eq(before.reserved_retention_bytes, 12L)
  assert_eq(before.reserved_execution_bytes, 27L)
  // Capturing twice cannot return scratch; pending cleanup is still the same
  // original reservation. A competing one-unit reservation must not fit.
  @resources.mark_cleanup_pending(ledger, reservation).unwrap()
  settle_row_capture_capacity(true, physical).unwrap()
  assert_true(@resources.reservation_pending(reservation))
  assert_true(
    @resources.reserve_capacity(ledger, 1L, 0L)
    is Err(@resources.RetentionLimit),
  )
  assert_true(
    @resources.reserve_capacity(ledger, 0L, 1L)
    is Err(@resources.ExecutionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // This primitive fixture explicitly performs the original cleanup ACK.
  // A production cancellation/callback return is not such an ACK.
  @resources.release_allocation(ledger, holding).unwrap()
  @resources.settle_reservation(ledger, reservation).unwrap()
  let retired = @resources.ledger_usage(ledger)
  assert_eq(retired.held_bytes, 0L)
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_true(
    settle_row_capture_capacity(true, physical)
    is Err(Physical(ClosedReservation)),
  )
  assert_eq(@resources.ledger_usage(ledger), retired)
}

///|
test "nonlisting capture keeps its prior settlement with no supplementary fields" {
  let ledger = listing_capacity_ledger(18L, 27L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 18L, 27L).unwrap()
  let holding = @resources.retain_allocation(ledger, reservation, 6L).unwrap()
  let physical : RowPhysical = {
    ledger,
    reservation,
    execution_scratch: 5L,
    provider_capacity: None,
    holding: Some(holding),
    dag: None,
    cleanup_confirmed: None,
  }
  settle_row_capture_capacity(false, physical).unwrap()
  assert_false(@resources.reservation_open(reservation))
  let settled = @resources.ledger_usage(ledger)
  assert_eq(settled.held_bytes, 6L)
  assert_eq(settled.reserved_retention_bytes, 0L)
  assert_eq(settled.reserved_execution_bytes, 0L)
  @resources.release_allocation(ledger, holding).unwrap()
}
