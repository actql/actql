///|
test "original keyed child uses exact assembly custody and one physical child per distinct accepted key" {
  let ledger = create_ledger({
    planning_work: 3,
    attempts: 4,
    holdings: 3,
    transfer_bytes: 0L,
    retained_bytes: 30L,
    execution_bytes: 30L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 3, 0).unwrap()
  let source = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  let direct_holding = retain_allocation(ledger, source, 0L).unwrap()
  settle_reservation(ledger, source).unwrap()
  let assembly = reserve_attempt(ledger, 0L, 7L, 5L).unwrap()
  assert_true(
    original_keyed_child_preparation_available(identity, ledger, assembly, 0),
  )
  let before = ledger_usage(ledger)
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, source, 0),
  )
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, -1),
  )
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 1),
  )
  let (foreign, foreign_identity, foreign_source, foreign_holding) = original_captured_prefix_fixture(
    0L,
  )
  assert_false(
    original_keyed_child_preparation_available(
      foreign_identity, ledger, assembly, 0,
    ),
  )
  assert_false(
    original_keyed_child_preparation_available(identity, foreign, assembly, 0),
  )
  assert_eq(ledger_usage(ledger), before)
  // Current retained boundary is independently 30 - bootstrap3 - assembly7.
  // One byte too many fails without spending the next child opportunity.
  assert_true(reserve_attempt(ledger, 0L, 21L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    original_keyed_child_preparation_available(identity, ledger, assembly, 0),
  )
  // Independent lifetime amounts only, not physical Model coefficients.
  let child = reserve_attempt(ledger, 0L, 4L, 3L).unwrap()
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 0),
  )
  mark_cleanup_pending(ledger, child).unwrap()
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 1),
  )
  let holding = retain_allocation(ledger, child, 1L).unwrap()
  settle_reservation(ledger, child).unwrap()
  assert_true(
    original_keyed_child_preparation_available(identity, ledger, assembly, 1),
  )
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 0),
  )
  release_allocation(ledger, holding).unwrap()
  // Lost child custody cannot be concealed by an accepted cache count.
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 1),
  )
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger.next_attempt_serial, Some(3))
  release_allocation(ledger, direct_holding).unwrap()
  settle_reservation(ledger, assembly).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(
    original_keyed_child_preparation_available(identity, ledger, assembly, 1),
  )
  release_allocation(foreign, foreign_holding).unwrap()
  assert_false(reservation_open(foreign_source))
  assert_true(finish_original_ledger_inventory(foreign, true).unwrap())
}
