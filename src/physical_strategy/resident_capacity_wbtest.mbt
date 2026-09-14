///|
test "resident DB reservation survives readers retirement and pending cleanup" {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let db = reserve_resident_capacity(ledger, 80L).unwrap()
  let table = allocate_resident_capacity(db, 60L).unwrap()
  // DB tables share the DB envelope; separate Host copies remain chargeable.
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 80L)
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  assert_true(allocate_resident_capacity(db, 21L) is Err(RetentionLimit))
  borrow_resident_capacity(db, table).unwrap()
  borrow_resident_capacity(db, table).unwrap()
  retire_resident_capacity(table)
  assert_eq(borrow_resident_capacity(db, table), Err(ClosedHolding))
  assert_eq(release_resident_capacity(table), Err(InvalidCharge))
  close_resident_capacity(db).unwrap()
  assert_true(reservation_pending(db.reservation))
  assert_eq(settle_resident_capacity(db), Err(InvalidCharge))
  return_resident_capacity(table).unwrap()
  assert_eq(release_resident_capacity(table), Err(InvalidCharge))
  return_resident_capacity(table).unwrap()
  release_resident_capacity(table).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 80L)
  settle_resident_capacity(db).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 1)
}

///|
test "resident capacity rejects foreign owners and never refunds spent transfer" {
  let ledger = create_ledger({
    planning_work: 10,
    attempts: 4,
    holdings: 4,
    transfer_bytes: 100L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let first = reserve_resident_capacity(ledger, 40L).unwrap()
  let second = reserve_resident_capacity(ledger, 40L).unwrap()
  let table = allocate_resident_capacity(first, 40L).unwrap()
  assert_eq(borrow_resident_capacity(second, table), Err(ForeignOwner))
  assert_true(reserve_resident_capacity(ledger, 21L) is Err(ExecutionLimit))
  let transfer = reserve_attempt(ledger, 20L, 0L, 0L).unwrap()
  charge_transfer(ledger, transfer, 12L).unwrap()
  settle_reservation(ledger, transfer).unwrap()
  retire_resident_capacity(table)
  release_resident_capacity(table).unwrap()
  close_resident_capacity(first).unwrap()
  settle_resident_capacity(first).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 40L)
  assert_eq(ledger_usage(ledger).transferred_bytes, 12L)
  assert_true(allocate_resident_capacity(first, 1L) is Err(ClosedReservation))
}
