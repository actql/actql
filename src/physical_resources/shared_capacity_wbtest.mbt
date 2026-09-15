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
  let db = reserve_shared_capacity(ledger, 80L).unwrap()
  let table = allocate_shared_capacity(db, 60L).unwrap()
  // DB tables share the DB envelope; separate Host copies remain chargeable.
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 80L)
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
  assert_true(allocate_shared_capacity(db, 21L) is Err(RetentionLimit))
  let first_borrow = borrow_shared_capacity(db, table).unwrap()
  let second_borrow = borrow_shared_capacity(db, table).unwrap()
  retire_shared_capacity(table)
  assert_true(borrow_shared_capacity(db, table) is Err(ClosedHolding))
  assert_eq(release_shared_capacity(table), Err(InvalidCharge))
  close_shared_capacity(db).unwrap()
  assert_true(reservation_pending(db.reservation))
  assert_eq(settle_shared_capacity(db), Err(InvalidCharge))
  return_shared_capacity(first_borrow).unwrap()
  assert_eq(release_shared_capacity(table), Err(InvalidCharge))
  assert_eq(return_shared_capacity(first_borrow), Err(InvalidCharge))
  return_shared_capacity(second_borrow).unwrap()
  release_shared_capacity(table).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 80L)
  settle_shared_capacity(db).unwrap()
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
  let first = reserve_shared_capacity(ledger, 40L).unwrap()
  let second = reserve_shared_capacity(ledger, 40L).unwrap()
  let table = allocate_shared_capacity(first, 40L).unwrap()
  assert_true(borrow_shared_capacity(second, table) is Err(ForeignOwner))
  assert_true(reserve_shared_capacity(ledger, 21L) is Err(ExecutionLimit))
  let transfer = reserve_attempt(ledger, 20L, 0L, 0L).unwrap()
  charge_transfer(ledger, transfer, 12L).unwrap()
  settle_reservation(ledger, transfer).unwrap()
  retire_shared_capacity(table)
  release_shared_capacity(table).unwrap()
  close_shared_capacity(first).unwrap()
  settle_shared_capacity(first).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 40L)
  assert_eq(ledger_usage(ledger).transferred_bytes, 12L)
  assert_true(allocate_shared_capacity(first, 1L) is Err(ClosedReservation))
}
