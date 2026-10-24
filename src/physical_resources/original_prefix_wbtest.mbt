///|
test "original prefix prerequisite rejects issued descriptor even before read funding" {
  let ledger = read_capacity_fixture(10L, 7L)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  assert_true(original_ledger_prefix_available(identity))
  issue_recorded_original_ledger_descriptor(
    identity,
    original_read_test_origin(),
  ).unwrap()
  |> ignore
  let before = ledger_usage(ledger)
  assert_false(original_ledger_prefix_available(identity))
  assert_eq(ledger_usage(ledger), before)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(original_ledger_prefix_available(identity))
}

///|
test "original prefix prerequisite never revives spent zero-byte identities" {
  for capacity_only in [false, true] {
    let ledger = read_capacity_fixture(10L, 7L)
    let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
    let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
    assert_true(original_ledger_prefix_available(identity))
    if capacity_only {
      let child = reserve_capacity(ledger, 0L, 0L).unwrap()
      settle_capacity(ledger, child).unwrap()
      assert_eq(ledger_usage(ledger).attempts, 0)
    } else {
      let child = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
      mark_cleanup_pending(ledger, child).unwrap()
      assert_false(original_ledger_prefix_available(identity))
      settle_reservation(ledger, child).unwrap()
      assert_eq(ledger_usage(ledger).attempts, 0)
      assert_eq(ledger.next_attempt_serial, Some(1))
    }
    let before = ledger_usage(ledger)
    assert_false(original_ledger_prefix_available(identity))
    assert_eq(ledger_usage(ledger), before)
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  }
}

///|
test "original prefix prerequisite refuses closing and foreign nominal inventory" {
  let ledger = read_capacity_fixture(10L, 7L)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0).unwrap()
  let foreign : OriginalLedgerIdentity = { ledger, bootstrap, }
  assert_false(original_ledger_prefix_available(foreign))
  assert_true(original_ledger_prefix_available(identity))
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  assert_false(original_ledger_prefix_available(identity))
  assert_true(capacity_reservation_open(bootstrap))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
