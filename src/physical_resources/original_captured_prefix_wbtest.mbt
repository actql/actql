///|
fn original_captured_prefix_fixture(
  bytes : Int64,
) -> (Ledger, OriginalLedgerIdentity, Reservation, Holding) {
  // Independent small token/lifetime values, not a physical Model profile.
  let ledger = read_capacity_fixture(30L, 30L)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 2, 0).unwrap()
  let source = reserve_attempt(ledger, 0L, bytes, 0L).unwrap()
  let holding = retain_allocation(ledger, source, bytes).unwrap()
  settle_reservation(ledger, source).unwrap()
  (ledger, identity, source, holding)
}

///|
test "original captured prefix requires exact source tokens including an empty holding" {
  for bytes in [0L, 1L] {
    let (ledger, identity, source, holding) = original_captured_prefix_fixture(
      bytes,
    )
    let (foreign, foreign_identity, foreign_source, foreign_holding) = original_captured_prefix_fixture(
      bytes,
    )
    let before = ledger_usage(ledger)
    assert_true(original_ledger_preparation_available(identity))
    assert_true(original_captured_prefix_available(ledger, source, holding))
    assert_false(
      original_captured_prefix_available(ledger, foreign_source, holding),
    )
    assert_false(
      original_captured_prefix_available(ledger, source, foreign_holding),
    )
    assert_false(original_captured_prefix_available(foreign, source, holding))
    assert_eq(ledger_usage(ledger), before)
    release_allocation(ledger, holding).unwrap()
    assert_false(original_captured_prefix_available(ledger, source, holding))
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
    assert_false(original_ledger_preparation_available(identity))
    release_allocation(foreign, foreign_holding).unwrap()
    assert_true(finish_original_ledger_inventory(foreign, true).unwrap())
    assert_false(original_ledger_preparation_available(foreign_identity))
  }
}

///|
test "original captured prefix rejects read issuance and pending original cleanup" {
  for issue_read in [false, true] {
    let (ledger, identity, source, holding) = original_captured_prefix_fixture(
      0L,
    )
    assert_true(original_captured_prefix_available(ledger, source, holding))
    if issue_read {
      issue_recorded_original_ledger_descriptor(
        identity,
        original_read_test_origin(),
      ).unwrap()
      |> ignore
    } else {
      assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
    }
    let before = ledger_usage(ledger)
    assert_false(original_ledger_preparation_available(identity))
    assert_false(original_captured_prefix_available(ledger, source, holding))
    assert_eq(ledger_usage(ledger), before)
    release_allocation(ledger, holding).unwrap()
    assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  }
}

///|
test "original captured prefix reserve failure is retryable but spent prefix never revives" {
  let (ledger, identity, source, holding) = original_captured_prefix_fixture(1L)
  let before = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 27L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  assert_true(original_captured_prefix_available(ledger, source, holding))
  let prefix = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  mark_cleanup_pending(ledger, prefix).unwrap()
  assert_false(original_captured_prefix_available(ledger, source, holding))
  settle_reservation(ledger, prefix).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger.next_attempt_serial, Some(2))
  assert_true(original_ledger_preparation_available(identity))
  assert_false(original_captured_prefix_available(ledger, source, holding))
  release_allocation(ledger, holding).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original keyed assembly prerequisite keeps the exact captured child and spent identity" {
  let (ledger, identity, _, holding) = original_captured_prefix_fixture(0L)
  let before = ledger_usage(ledger)
  assert_true(original_ledger_captured_preparation_available(identity))
  assert_eq(ledger_usage(ledger), before)
  // A rejected allocation does not spend the original assembly opportunity.
  assert_true(reserve_attempt(ledger, 0L, 28L, 0L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  assert_true(original_ledger_captured_preparation_available(identity))
  let assembly = reserve_attempt(ledger, 0L, 7L, 5L).unwrap()
  mark_cleanup_pending(ledger, assembly).unwrap()
  assert_false(original_ledger_captured_preparation_available(identity))
  assert_true(holding_available(ledger, holding))
  assert_true(reservation_open(assembly))
  settle_reservation(ledger, assembly).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger.next_attempt_serial, Some(2))
  assert_false(original_ledger_captured_preparation_available(identity))
  release_allocation(ledger, holding).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(original_ledger_captured_preparation_available(identity))
}

///|
test "captured prefix borrows live original Source backing but never pending or foreign tokens" {
  let ledger = read_capacity_fixture(30L, 30L)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 2, 0).unwrap()
  let source = reserve_attempt(ledger, 0L, 4L, 5L).unwrap()
  let holding = retain_allocation(ledger, source, 1L).unwrap()
  let before = ledger_usage(ledger)
  assert_true(reservation_open(source))
  assert_true(original_captured_prefix_available(ledger, source, holding))
  assert_eq(ledger_usage(ledger), before)
  let (foreign, _, foreign_source, foreign_holding) = original_captured_prefix_fixture(
    1L,
  )
  assert_false(
    original_captured_prefix_available(ledger, foreign_source, holding),
  )
  assert_false(
    original_captured_prefix_available(ledger, source, foreign_holding),
  )
  let prefix = reserve_attempt(ledger, 0L, 2L, 3L).unwrap()
  assert_false(original_captured_prefix_available(ledger, source, holding))
  assert_true(
    original_captured_prefix_reservation_available(
      ledger, source, holding, prefix,
    ),
  )
  let combined = ledger_usage(ledger)
  assert_eq(
    combined.reserved_retention_bytes,
    before.reserved_retention_bytes + 2L,
  )
  assert_eq(
    combined.reserved_execution_bytes,
    before.reserved_execution_bytes + 3L,
  )
  assert_false(
    original_captured_prefix_reservation_available(
      ledger, source, holding, foreign_source,
    ),
  )
  mark_cleanup_pending(ledger, source).unwrap()
  assert_false(
    original_captured_prefix_reservation_available(
      ledger, source, holding, prefix,
    ),
  )
  assert_eq(ledger_usage(ledger), combined)
  settle_reservation(ledger, prefix).unwrap()
  // Spending and retiring the dependent cannot refill the first opportunity.
  assert_false(original_captured_prefix_available(ledger, source, holding))
  release_allocation(ledger, holding).unwrap()
  settle_reservation(ledger, source).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  release_allocation(foreign, foreign_holding).unwrap()
  assert_true(finish_original_ledger_inventory(foreign, true).unwrap())
  assert_false(original_ledger_preparation_available(identity))
}
