///|
// Pure refusal arithmetic within the existing Model owner. These scalar
// counts issue no original startup, physical Ledger, grant or restore proof.
test "shared Mock cap counts authenticated saved and Unknown attempts as spent" {
  let bound : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 4,
    holdings: 0,
    transfer_bytes: 4000L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  assert_eq(check_original_mock_attempt_budget(bound, 1, 1, 1, 1000L), Ok(()))
  assert_true(
    check_original_mock_attempt_budget(
      { ..bound, attempts: 3, },
      1,
      1,
      1,
      1000L,
    )
    is Err(Ledger(@resources.AttemptLimit)),
  )
  assert_true(
    check_original_mock_attempt_budget(
      { ..bound, transfer_bytes: 3999L, },
      1,
      1,
      1,
      1000L,
    )
    is Err(Ledger(@resources.TransferLimit)),
  )
  // Even one slot can retain both an entered Unknown and a reconciliation
  // read reservation. Closing another token cannot erase either history.
  assert_true(
    check_original_mock_attempt_budget(
      { ..bound, attempts: 2, },
      1,
      0,
      1,
      1000L,
    )
    is Err(Ledger(@resources.AttemptLimit)),
  )
  assert_true(
    check_original_mock_attempt_budget(bound, 2147483647, 2147483647, 0, 0L)
    is Err(Ledger(@resources.AttemptLimit)),
  )
}
