///|
test "original Writer preparation guard is repeatable without issuing or charging" {
  let (ledger, identity, origin) = original_state_write_fixture(17)
  let usage = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  for _ in 0..<3 {
    assert_true(check_original_state_write_preparation(identity) is Ok(_))
    assert_eq(ledger_usage(ledger), usage)
    assert_eq(ledger.next_capacity_serial, serial)
    assert_false(ledger.original_inventory.unwrap().descriptor_issued)
    assert_false(ledger.original_inventory.unwrap().read_claimed)
  }
  // The same existing issuer still charges once and owns the resulting claim.
  let writer = @encode.writer(1000, 200, 10)
  let (claim, cursor) = prepare_original_state_write(
    identity, origin, writer, 7L, 5L,
  ).unwrap()
  let after = ledger_usage(ledger)
  assert_true(
    check_original_state_write_preparation(identity)
    is Err(Original(SpentClaim)),
  )
  assert_eq(ledger_usage(ledger), after)
  assert_eq(finish_original_state_test_writer(cursor, 1), 17)
  assert_eq(@encode.finish(writer), original_document_test_wire())
  settle_funded_read(claim, true).unwrap()
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original Writer preparation guard refuses copied identity and foreign bootstrap" {
  let (ledger, identity, _) = original_state_write_fixture(17)
  let (other, other_identity, _) = original_state_write_fixture(17)
  let copied : OriginalLedgerIdentity = {
    ledger,
    bootstrap: identity.bootstrap,
  }
  let swapped : OriginalLedgerIdentity = {
    ledger,
    bootstrap: other_identity.bootstrap,
  }
  let before = ledger_usage(ledger)
  let other_before = ledger_usage(other)
  for invalid in [copied, swapped] {
    assert_true(
      check_original_state_write_preparation(invalid)
      is Err(Original(ForeignOrigin)),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger_usage(other), other_before)
    assert_eq(ledger.next_capacity_serial, Some(-2))
    assert_eq(other.next_capacity_serial, Some(-2))
  }
  // An independent genuine identity is valid for its own Ledger, not this one.
  assert_true(check_original_state_write_preparation(identity) is Ok(_))
  assert_true(check_original_state_write_preparation(other_identity) is Ok(_))
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(finish_original_ledger_inventory(other, true).unwrap())
}

///|
test "original Writer preparation guard keeps pending cleanup and refuses retirement" {
  let (ledger, identity, _) = original_state_write_fixture(17)
  let before = ledger_usage(ledger)
  assert_false(finish_original_ledger_inventory(ledger, false).unwrap())
  for _ in 0..<2 {
    assert_true(
      check_original_state_write_preparation(identity)
      is Err(Original(ChangedOriginalState)),
    )
    assert_eq(ledger_usage(ledger), before)
    assert_eq(ledger.next_capacity_serial, Some(-2))
    assert_true(capacity_reservation_open(identity.bootstrap))
  }
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_false(capacity_reservation_open(identity.bootstrap))
  assert_true(
    check_original_state_write_preparation(identity)
    is Err(Original(ForeignOrigin)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "original Writer preparation guard cannot retire bootstrap before owning cleanup" {
  let (ledger, identity, _) = original_state_write_fixture(17)
  let before = ledger_usage(ledger)
  assert_true(settle_capacity(ledger, identity.bootstrap) is Err(InvalidCharge))
  assert_true(check_original_state_write_preparation(identity) is Ok(_))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_false(ledger.original_inventory.unwrap().descriptor_issued)
  assert_false(ledger.original_inventory.unwrap().read_claimed)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}

///|
test "original Writer preparation guard preserves one-shot refusal after capacity failure" {
  let (ledger, identity, origin) = original_state_write_fixture(17)
  assert_true(check_original_state_write_preparation(identity) is Ok(_))
  let writer = @encode.writer(1000, 200, 10)
  assert_true(
    prepare_original_state_write(identity, origin, writer, 8L, 5L)
    is Err(Original(Resource(RetentionLimit))),
  )
  let before = ledger_usage(ledger)
  assert_eq(before.planning_work, 17)
  assert_eq(before.reserved_retention_bytes, 3L)
  assert_eq(before.reserved_execution_bytes, 2L)
  assert_true(
    check_original_state_write_preparation(identity)
    is Err(Original(SpentClaim)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, Some(-2))
  assert_eq(@encode.writer_progress(writer), (0, 0, 0))
  @encode.cancel_writer(writer)
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
}
