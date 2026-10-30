///|
test "managed cleanup retains zero-byte live reservations before report or stop" {
  for attempt in [false, true] {
    let (admission, _, ledger, _, _, _, reports) = managed_run_bootstrap_fixture()
    let before_attempts = ledger_usage(ledger).attempts
    if attempt {
      let reservation = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
      let before = ledger_usage(ledger)
      assert_eq(cleanup_node_managed_run_admission(admission), Err(Unavailable))
      assert_eq(ledger_usage(ledger), before)
      assert_eq(reports.length(), 0)
      assert_false(admission.child.stop_attempted)
      settle_reservation(ledger, reservation).unwrap()
    } else {
      let reservation = reserve_capacity(ledger, 0L, 0L).unwrap()
      let before = ledger_usage(ledger)
      assert_eq(cleanup_node_managed_run_admission(admission), Err(Unavailable))
      assert_eq(ledger_usage(ledger), before)
      assert_eq(reports.length(), 0)
      assert_false(admission.child.stop_attempted)
      settle_capacity(ledger, reservation).unwrap()
    }
    let final_usage = ledger_usage(ledger)
    // An unused attempt reservation returns its existing reservation; the
    // distinct control below starts work and keeps actual consumed history.
    assert_eq(final_usage.attempts, before_attempts)
    cleanup_node_managed_run_admission(admission).unwrap()
    assert_eq(reports, [final_usage])
    assert_true(admission.child.stop_attempted)
    cleanup_node_managed_run_admission(admission).unwrap()
    assert_eq(reports.length(), 1)
    assert_eq(ledger_usage(ledger), final_usage)
  }
}

///|
test "managed cleanup keeps zero-byte holdings live and reports spent history unchanged" {
  let (admission, _, ledger, _, _, _, reports) = managed_run_bootstrap_fixture()
  charge_planning(ledger, 2).unwrap()
  let reservation = reserve_attempt(ledger, 3L, 0L, 0L).unwrap()
  let holding = retain_allocation(ledger, reservation, 0L).unwrap()
  charge_transfer(ledger, reservation, 3L).unwrap()
  settle_reservation(ledger, reservation).unwrap()
  let before = ledger_usage(ledger)
  assert_eq(before.held_bytes, 0L)
  assert_eq(before.holdings, 1)
  assert_eq(cleanup_node_managed_run_admission(admission), Err(Unavailable))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(reports.length(), 0)
  assert_false(admission.child.stop_attempted)
  release_allocation(ledger, holding).unwrap()
  let final_usage = ledger_usage(ledger)
  cleanup_node_managed_run_admission(admission).unwrap()
  assert_eq(reports, [final_usage])
  assert_eq(final_usage.planning_work, 2)
  assert_eq(final_usage.attempts, 1)
  assert_eq(final_usage.transferred_bytes, 3L)
  assert_eq(ledger_usage(ledger), final_usage)
}
