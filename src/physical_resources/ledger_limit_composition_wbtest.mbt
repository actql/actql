///|
test "typed Ledger limit composition preserves independent dimensions and inputs" {
  let first : LedgerLimits = {
    planning_work: 1,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 4L,
    retained_bytes: 5L,
    execution_bytes: 6L,
  }
  let second : LedgerLimits = {
    planning_work: 7,
    attempts: 8,
    holdings: 9,
    transfer_bytes: 10L,
    retained_bytes: 11L,
    execution_bytes: 12L,
  }
  assert_eq(
    add_ledger_limits(first, second),
    Some({
      planning_work: 8,
      attempts: 10,
      holdings: 12,
      transfer_bytes: 14L,
      retained_bytes: 16L,
      execution_bytes: 18L,
    }),
  )
  assert_eq(add_ledger_limits(second, first), add_ledger_limits(first, second))
  assert_eq(first.retained_bytes, 5L)
  assert_eq(second.execution_bytes, 12L)
  let zero : LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  // Ledger dimensions are independent; this DATA fold must not impose the
  // different retained-alongside-execution projection on these limits.
  assert_eq(
    add_ledger_limits(zero, { ..zero, retained_bytes: 100L, }),
    Some({ ..zero, retained_bytes: 100L, }),
  )
}

///|
test "typed Ledger limit composition refuses negative credit and exact boundary overflow" {
  let zero : LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  let maximum : LedgerLimits = {
    planning_work: 2147483647,
    attempts: 2147483647,
    holdings: 2147483647,
    transfer_bytes: 9223372036854775807L,
    retained_bytes: 9223372036854775807L,
    execution_bytes: 9223372036854775807L,
  }
  assert_eq(add_ledger_limits(maximum, zero), Some(maximum))
  for
    one in [
      { ..zero, planning_work: 1, },
      { ..zero, attempts: 1, },
      { ..zero, holdings: 1, },
      { ..zero, transfer_bytes: 1L, },
      { ..zero, retained_bytes: 1L, },
      { ..zero, execution_bytes: 1L, },
    ] {
    assert_true(add_ledger_limits(maximum, one) is None)
    assert_true(add_ledger_limits(one, maximum) is None)
  }
  for
    invalid in [
      { ..zero, planning_work: -1, },
      { ..zero, attempts: -1, },
      { ..zero, holdings: -1, },
      { ..zero, transfer_bytes: -1L, },
      { ..zero, retained_bytes: -1L, },
      { ..zero, execution_bytes: -1L, },
    ] {
    assert_true(add_ledger_limits(maximum, invalid) is None)
    assert_true(add_ledger_limits(invalid, maximum) is None)
  }
}
