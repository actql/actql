///|
test "original prefixed keyed census requires exact live prefix and physical downstream retirement" {
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
  assert_true(
    original_ledger_captured_preparation_available(
      identity,
      prefix=Some(prefix),
    ),
  )
  assert_false(original_ledger_captured_preparation_available(identity))
  assert_false(
    original_ledger_captured_preparation_available(
      identity,
      prefix=Some(source),
    ),
  )
  let assembly = reserve_attempt(ledger, 0L, 7L, 7L).unwrap()
  assert_true(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 0),
  )
  assert_false(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      prefix,
      0,
      prefix=Some(assembly),
    ),
  )
  let before = ledger_usage(ledger)
  // Independent sum: 30 - bootstrap3 - Source1 - prefix5 - assembly7 = 14.
  assert_true(reserve_attempt(ledger, 0L, 15L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  let child = reserve_attempt(ledger, 0L, 14L, 3L).unwrap()
  assert_false(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  let holding = retain_allocation(ledger, child, 1L).unwrap()
  settle_reservation(ledger, child).unwrap()
  assert_true(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      1,
      prefix=Some(prefix),
    ),
  )
  assert_false(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      0,
      prefix=Some(prefix),
    ),
  )
  assert_false(original_keyed_prefix_dependents_retired(ledger, prefix))
  settle_reservation(ledger, assembly).unwrap()
  // A closing Scope is not a physical child close acknowledgement.
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_false(original_keyed_prefix_dependents_retired(ledger, prefix))
  release_allocation(ledger, holding).unwrap()
  assert_true(original_keyed_prefix_dependents_retired(ledger, prefix))
  mark_cleanup_pending(ledger, prefix).unwrap()
  // Cleanup may query actual retirement even when new use is forbidden.
  assert_false(
    original_keyed_child_preparation_available(
      identity,
      ledger,
      assembly,
      1,
      prefix=Some(prefix),
    ),
  )
  settle_reservation(ledger, prefix).unwrap()
  release_allocation(ledger, source_holding).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger.next_attempt_serial, Some(4))
  assert_eq(ledger_usage(ledger).holdings, 0)
  assert_eq(ledger.next_holding_serial, Some(2))
  assert_eq(ledger_usage(ledger).held_bytes, 0L)
}
