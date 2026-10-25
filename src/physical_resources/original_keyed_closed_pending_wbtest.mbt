///|
test "original keyed prefix retires an acknowledged closed pending assembly only after its holding release" {
  let ledger = create_ledger({
    planning_work: 3,
    attempts: 3,
    holdings: 2,
    transfer_bytes: 0L,
    retained_bytes: 30L,
    execution_bytes: 30L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  ignore(begin_original_ledger_inventory(ledger, bootstrap, 3, 2, 0).unwrap())
  let source = reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  let source_holding = retain_allocation(ledger, source, 1L).unwrap()
  settle_reservation(ledger, source).unwrap()
  let prefix = reserve_attempt(ledger, 0L, 5L, 5L).unwrap()
  let assembly = reserve_attempt(ledger, 0L, 7L, 7L).unwrap()
  let assembly_holding = retain_allocation(ledger, assembly, 1L).unwrap()
  mark_cleanup_pending(ledger, assembly).unwrap()
  let pending = ledger_usage(ledger)
  assert_false(original_keyed_prefix_dependents_retired(ledger, prefix))
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_eq(ledger_usage(ledger), pending)
  // The existing trusted cleanup ACK closes the reservation, not its retained
  // output. The historical flag remains set; it is not a new live obligation.
  settle_reservation(ledger, assembly).unwrap()
  assert_false(reservation_open(assembly))
  assert_true(assembly.cleanup_pending)
  assert_false(reservation_pending(assembly))
  assert_false(original_keyed_prefix_dependents_retired(ledger, prefix))
  release_allocation(ledger, assembly_holding).unwrap()
  assert_true(original_keyed_prefix_dependents_retired(ledger, prefix))
  assert_eq(ledger_usage(ledger).held_bytes, 1L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 8L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 7L)
  settle_reservation(ledger, prefix).unwrap()
  release_allocation(ledger, source_holding).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  let cleaned = ledger_usage(ledger)
  assert_eq(cleaned.attempts, 0)
  assert_eq(ledger.next_attempt_serial, Some(3))
  assert_eq(cleaned.holdings, 0)
  assert_eq(ledger.next_holding_serial, Some(2))
  assert_eq(cleaned.held_bytes, 0L)
  assert_eq(cleaned.reserved_retention_bytes, 0L)
  assert_eq(cleaned.reserved_execution_bytes, 0L)
}
