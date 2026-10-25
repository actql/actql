///|
test "original whole keyed suffix requires actual assembly holding and keeps pending downstream custody" {
  // Independently authored ledger units, not a physical Model layout grant.
  let ledger = create_ledger({
    planning_work: 3,
    attempts: 5,
    holdings: 3,
    transfer_bytes: 0L,
    retained_bytes: 30L,
    execution_bytes: 30L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 5, 3, 0).unwrap()
  let source = reserve_attempt(ledger, 0L, 1L, 1L).unwrap()
  let source_holding = retain_allocation(ledger, source, 1L).unwrap()
  settle_reservation(ledger, source).unwrap()
  let prefix = reserve_attempt(ledger, 0L, 5L, 5L).unwrap()
  let assembly = reserve_attempt(ledger, 0L, 7L, 7L).unwrap()
  let child = reserve_attempt(ledger, 0L, 2L, 2L).unwrap()
  let child_holding = retain_allocation(ledger, child, 1L).unwrap()
  settle_reservation(ledger, child).unwrap()
  assert_false(
    original_keyed_serialization_preparation_available(
      identity, ledger, prefix, assembly, 1,
    ),
  )
  let assembly_holding = retain_allocation(ledger, assembly, 1L).unwrap()
  assert_false(
    original_keyed_serialization_preparation_available(
      identity, ledger, prefix, assembly, 1,
    ),
  )
  settle_reservation(ledger, assembly).unwrap()
  assert_true(
    original_keyed_serialization_preparation_available(
      identity, ledger, prefix, assembly, 1,
    ),
  )
  assert_false(
    original_keyed_serialization_preparation_available(
      identity, ledger, assembly, prefix, 1,
    ),
  )
  for wrong_count in [0, 2] {
    assert_false(
      original_keyed_serialization_preparation_available(
        identity, ledger, prefix, assembly, wrong_count,
      ),
    )
  }
  let before = ledger_usage(ledger)
  // 30 - bootstrap3 - prefix5 - Source1 - child1 - assembly1 = 19.
  assert_true(reserve_attempt(ledger, 0L, 20L, 0L) is Err(RetentionLimit))
  // 30 - bootstrap2 - prefix5 = 23.
  assert_true(reserve_attempt(ledger, 0L, 19L, 24L) is Err(ExecutionLimit))
  assert_eq(ledger_usage(ledger), before)
  let suffix = reserve_attempt(ledger, 0L, 19L, 23L).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 27L)
  assert_eq(ledger_usage(ledger).held_bytes, 3L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 30L)
  assert_false(original_keyed_lookup_dependents_retired(ledger, assembly))
  assert_false(
    original_keyed_serialization_preparation_available(
      identity, ledger, prefix, assembly, 1,
    ),
  )
  mark_cleanup_pending(ledger, suffix).unwrap()
  let pending = ledger_usage(ledger)
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_eq(ledger_usage(ledger), pending)
  assert_false(original_keyed_lookup_dependents_retired(ledger, assembly))
  assert_false(original_keyed_prefix_dependents_retired(ledger, prefix))
  // A confirmed same-owner retry, not Scope closing, retires the suffix.
  settle_reservation(ledger, suffix).unwrap()
  assert_true(original_keyed_lookup_dependents_retired(ledger, assembly))
  assert_false(original_keyed_prefix_dependents_retired(ledger, prefix))
  release_allocation(ledger, assembly_holding).unwrap()
  release_allocation(ledger, child_holding).unwrap()
  assert_true(original_keyed_prefix_dependents_retired(ledger, prefix))
  settle_reservation(ledger, prefix).unwrap()
  release_allocation(ledger, source_holding).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  let cleaned = ledger_usage(ledger)
  assert_eq(cleaned.attempts, 0)
  assert_eq(ledger.next_attempt_serial, Some(5))
  assert_eq(cleaned.holdings, 0)
  assert_eq(ledger.next_holding_serial, Some(3))
  assert_eq(cleaned.held_bytes, 0L)
  assert_eq(cleaned.reserved_retention_bytes, 0L)
  assert_eq(cleaned.reserved_execution_bytes, 0L)
}
