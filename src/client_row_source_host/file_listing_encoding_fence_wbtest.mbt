///|
// Actual same-Ledger reserve/mark-pending/settle functions. This is a necessary
// lifetime predicate fixture, not Source authority or a Node physical profile.
test "listing encoding cannot reuse pending or settled Source execution" {
  let ledger = listing_capacity_ledger(18L, 27L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 18L, 27L).unwrap()
  let physical : RowPhysical = {
    ledger,
    reservation,
    execution_scratch: 5L,
    holding: None,
    dag: None,
    cleanup_confirmed: None,
  }
  let original = @resources.ledger_usage(ledger)
  assert_true(row_listing_encoding_reservation_live(physical))
  assert_eq(@resources.ledger_usage(ledger), original)
  settle_row_capture_capacity(true, physical).unwrap()
  assert_true(row_listing_encoding_reservation_live(physical))
  assert_eq(@resources.ledger_usage(ledger), original)
  @resources.mark_cleanup_pending(ledger, reservation).unwrap()
  assert_false(row_listing_encoding_reservation_live(physical))
  assert_eq(@resources.ledger_usage(ledger), original)
  // There is no predicate reset, fake receiver, refund or fresh token. The
  // original cleanup really settles this same pending reservation.
  @resources.settle_reservation(ledger, reservation).unwrap()
  let retired = @resources.ledger_usage(ledger)
  assert_false(row_listing_encoding_reservation_live(physical))
  assert_eq(retired.reserved_retention_bytes, 0L)
  assert_eq(retired.reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger), retired)
}
