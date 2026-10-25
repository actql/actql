///|
test "preparation constructor transitions retain dependencies and reserve peak not cumulative scratch" {
  let ledger = @resources.create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let capacity : @resources.PreparationCapacity[Array[Int], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    20L,
    50L,
    max_borrowers=1,
  ).unwrap()
  let other = @resources.reserve_capacity(ledger, 10L, 10L).unwrap()
  // Prior successful constructor returned; its live dependency remains in R.
  let source_peak = closed_values_execution_peak(50L, 20L, 5L).unwrap()
  assert_eq(source_peak, 50L)
  reserve_closed_values_phase(capacity, input, SourceParsing, 30L, source_peak).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 60L)
  let body_peak = closed_values_execution_peak(source_peak, 85L, 5L).unwrap()
  assert_eq(body_peak, 90L)
  reserve_closed_values_phase(
    capacity,
    input,
    CheckLowerAndPlan,
    40L,
    body_peak,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 50L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_eq(input[0], 1)
  // Another live owner still narrows capacity; max is not a release/grant.
  let over = closed_values_execution_peak(body_peak, 86L, 5L).unwrap()
  guard reserve_closed_values_phase(
      capacity,
      input,
      CheckLowerAndPlan,
      40L,
      over,
    )
    is Err(issue) else {
    fail("expected other-owner capacity refusal")
  }
  assert_eq(
    closed_values_preparation_capacity_refusal(issue),
    Some(("check_lower_and_plan", "execution", 40L, 91L, 90L, 90L)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 100L)
  assert_eq(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input),
    Ok(true),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 10L)
  @resources.settle_capacity(ledger, other).unwrap()
}

///|
test "preparation execution peak rejects negative and overflowing phase envelopes" {
  assert_eq(closed_values_execution_peak(-1L, 0L, 0L), None)
  assert_eq(closed_values_execution_peak(0L, -1L, 0L), None)
  assert_eq(closed_values_execution_peak(0L, 0L, -1L), None)
  assert_eq(closed_values_execution_peak(0L, 9223372036854775807L, 1L), None)
  assert_eq(
    closed_values_execution_peak(0L, 9223372036854775807L, 0L),
    Some(9223372036854775807L),
  )
}
