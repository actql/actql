///|
fn continuation_test_limits() -> LedgerLimits {
  {
    planning_work: 20,
    attempts: 4,
    holdings: 1,
    transfer_bytes: 10L,
    retained_bytes: 8L,
    execution_bytes: 8L,
  }
}

///|
fn continuation_test_wire() -> String {
  // Independently authored accounting record, not produced by the writer.
  "[\"actql-ledger-continuation/0.1\",[\"20\",\"4\",\"1\",\"10\",\"8\",\"8\"],[\"7\",\"1\",\"0\",\"2\",\"3\",\"0\",\"0\",\"0\",\"0\",\"8\",\"0\",\"0\",\"0\"],null,[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"2\",\"1\"],[\"0\",\"0\",\"0\"]]"
}

///|
fn continuation_test_decode(
  wire : String,
) -> Result[LedgerContinuationState, LedgerContinuationIssue] {
  admit_quiescent_ledger_state(original_document_test_cursor(wire))
}

///|
test "ledger continuation preserves cumulative debt and nonreused identities through real retirement" {
  let ledger = create_ledger(continuation_test_limits()).unwrap()
  charge_planning(ledger, 7).unwrap()
  let unused = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  settle_reservation(ledger, unused).unwrap()
  let reservation = reserve_attempt(ledger, 5L, 8L, 1L).unwrap()
  let holding = retain_allocation(ledger, reservation, 8L).unwrap()
  charge_transfer(ledger, reservation, 2L).unwrap()
  mark_transfer_uncertain(ledger, reservation, 3L).unwrap()
  settle_reservation(ledger, reservation).unwrap()
  release_allocation(ledger, holding).unwrap()
  for _ in 0..<2 {
    let capacity = reserve_capacity(ledger, 0L, 0L).unwrap()
    settle_capacity(ledger, capacity).unwrap()
  }
  let saved = capture_quiescent_ledger_state(ledger).unwrap()
  check_ledger_continuation_current(ledger, saved).unwrap()
  let writer = @encode.writer(2000, 100, 10)
  write_ledger_continuation_state(saved, writer).unwrap()
  assert_eq(@encode.finish(writer), continuation_test_wire())
  let decoded = continuation_test_decode(continuation_test_wire()).unwrap()
  let restored = create_ledger(continuation_test_limits()).unwrap()
  restore_quiescent_ledger_state(restored, decoded).unwrap()
  assert_eq(ledger_usage(restored), ledger_usage(ledger))
  assert_eq(
    restore_quiescent_ledger_state(restored, decoded),
    Err(AlreadyRestored),
  )
  assert_true(reserve_attempt(restored, 6L, 0L, 0L) is Err(TransferLimit))
  let next = reserve_attempt(restored, 5L, 0L, 0L).unwrap()
  assert_eq(reservation_serial(next), 2)
  consume_reserved_attempt(restored, next).unwrap()
  settle_reservation(restored, next).unwrap()
  let capacity = reserve_capacity(restored, 0L, 0L).unwrap()
  assert_eq(capacity.reservation.serial, -3)
  settle_capacity(restored, capacity).unwrap()
  let allocation = reserve_attempt(restored, 0L, 1L, 0L).unwrap()
  let held = retain_allocation(restored, allocation, 1L).unwrap()
  assert_eq(holding_serial(held), 1)
  settle_reservation(restored, allocation).unwrap()
  release_allocation(restored, held).unwrap()
}

///|
test "ledger continuation refuses zero-byte live reservations holdings and delegated originals" {
  let ledger = create_ledger(continuation_test_limits()).unwrap()
  let reservation = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  assert_true(capture_quiescent_ledger_state(ledger) is Err(PendingOriginal))
  let holding = retain_allocation(ledger, reservation, 0L).unwrap()
  settle_reservation(ledger, reservation).unwrap()
  assert_true(capture_quiescent_ledger_state(ledger) is Err(PendingOriginal))
  release_allocation(ledger, holding).unwrap()
  assert_true(capture_quiescent_ledger_state(ledger) is Ok(_))
  let delegation = reserve_execution_delegation(
    ledger,
    {
      planning_work: 1,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    },
    0L,
    0L,
  ).unwrap()
  assert_true(capture_quiescent_ledger_state(ledger) is Err(PendingOriginal))
  // No child stop or reclamation is fabricated to obtain another snapshot.
  assert_eq(execution_delegation_limits(delegation).planning_work, 1)
}

///|
test "ledger continuation rejects changed limits spent pristine targets and all-zero replay" {
  let saved = continuation_test_decode(continuation_test_wire()).unwrap()
  let foreign = create_ledger({ ..continuation_test_limits(), attempts: 5, }).unwrap()
  let before = ledger_usage(foreign)
  assert_eq(restore_quiescent_ledger_state(foreign, saved), Err(ChangedLimits))
  assert_eq(ledger_usage(foreign), before)
  let spent = create_ledger(continuation_test_limits()).unwrap()
  let prior = reserve_attempt(spent, 0L, 0L, 0L).unwrap()
  settle_reservation(spent, prior).unwrap()
  assert_eq(restore_quiescent_ledger_state(spent, saved), Err(NotPristine))
  let empty = create_ledger(continuation_test_limits()).unwrap()
  let zero = capture_quiescent_ledger_state(empty).unwrap()
  restore_quiescent_ledger_state(empty, zero).unwrap()
  assert_eq(restore_quiescent_ledger_state(empty, zero), Err(AlreadyRestored))
  assert_eq(ledger_usage(empty).attempts, 0)
}

///|
test "ledger continuation records Unknown quantity debt and actual overrun without granting allowance" {
  let ledger = create_ledger(continuation_test_limits()).unwrap()
  let limits = { tokens: 3L, cost_units: 4L, duration_ms: 5L, }
  configure_quantities(ledger, limits).unwrap()
  let reservation = reserve_attempt(ledger, 0L, 0L, 0L, quantities=Some(limits)).unwrap()
  mark_quantities_uncertain(ledger, reservation).unwrap()
  assert_true(
    observe_quantities(ledger, reservation, tokens=Some(7L)) is Err(TokenLimit),
  )
  assert_true(capture_quiescent_ledger_state(ledger) is Err(PendingOriginal))
  settle_reservation(ledger, reservation).unwrap()
  let original = quantity_usage(ledger)
  assert_eq(original.consumed.tokens, 7L)
  assert_eq(original.uncertain.cost_units, 4L)
  let saved = capture_quiescent_ledger_state(ledger).unwrap()
  let restored = create_ledger(continuation_test_limits()).unwrap()
  restore_quiescent_ledger_state(restored, saved).unwrap()
  assert_eq(quantity_usage(restored), original)
  assert_true(quantity_configuration_matches(restored, Some(limits)))
  assert_true(
    reserve_attempt(restored, 0L, 0L, 0L, quantities=Some(zero_quantities()))
    is Err(TokenLimit),
  )
}

///|
test "ledger continuation immutable snapshot is not a fence or an authentication receipt" {
  let ledger = create_ledger(continuation_test_limits()).unwrap()
  let saved = capture_quiescent_ledger_state(ledger).unwrap()
  charge_planning(ledger, 1).unwrap()
  assert_eq(
    check_ledger_continuation_current(ledger, saved),
    Err(ChangedOriginal),
  )
  assert_eq(saved.state.usage.planning_work, 0)
  let next = capture_quiescent_ledger_state(ledger).unwrap()
  check_ledger_continuation_current(ledger, next).unwrap()
  let capacity = reserve_capacity(ledger, 0L, 0L).unwrap()
  assert_eq(
    check_ledger_continuation_current(ledger, next),
    Err(ChangedOriginal),
  )
  settle_capacity(ledger, capacity).unwrap()
  assert_eq(
    check_ledger_continuation_current(ledger, next),
    Err(ChangedOriginal),
  )
}

///|
test "ledger continuation strict DATA admission rejects missing live fields overflow and serial rollback" {
  let original = continuation_test_wire()
  let usage = "[\"7\",\"1\",\"0\",\"2\",\"3\",\"0\",\"0\",\"0\",\"0\",\"8\",\"0\",\"0\",\"0\"]"
  let fields = ["7", "1", "0", "2", "3", "0", "0", "0", "0", "8", "0", "0", "0"]
  for index in [2, 5, 6, 7, 8, 10, 11, 12] {
    let changed = fields.copy()
    changed[index] = "1"
    let wire = original.replace(
      old=usage,
      new="[" + changed.map(value => "\"" + value + "\"").join(",") + "]",
    )
    assert_true(continuation_test_decode(wire) is Err(InvalidRecord))
  }
  for
    (old, new) in [
      ("\"-3\",\"2\",\"1\"", "\"0\",\"2\",\"1\""),
      ("\"-3\",\"2\",\"1\"", "\"-3\",\"0\",\"1\""),
      ("\"7\",\"1\",\"0\",\"2\",\"3\"", "\"7\",\"1\",\"0\",\"9\",\"3\""),
      (
        "\"7\",\"1\",\"0\",\"2\",\"3\"", "\"7\",\"1\",\"0\",\"9223372036854775808\",\"3\"",
      ),
      ("\"-3\",\"2\",\"1\"", "\"-03\",\"2\",\"1\""),
      ("\"0\",\"0\",\"0\"]]", "\"1\",\"0\",\"0\"]]"),
    ] {
    assert_true(original.contains(old))
    assert_true(
      continuation_test_decode(original.replace(old~, new~))
      is Err(InvalidRecord),
    )
  }
  assert_true(
    continuation_test_decode(
      original.replace(
        old=usage,
        new="[\"7\",\"1\",\"0\",\"2\",\"3\",\"0\",\"0\",\"0\",\"0\",\"8\"]",
      ),
    )
    is Err(InvalidRecord),
  )
}

///|
test "ledger continuation exhausted serials and one-short Writer never reset identity or debt" {
  let saved = continuation_test_decode(
    continuation_test_wire().replace(
      old="[\"-3\",\"2\",\"1\"]",
      new="[null,null,null]",
    ),
  ).unwrap()
  let ledger = create_ledger(continuation_test_limits()).unwrap()
  restore_quiescent_ledger_state(ledger, saved).unwrap()
  let before = ledger_usage(ledger)
  assert_true(reserve_attempt(ledger, 0L, 0L, 0L) is Err(IdentityOverflow))
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(InvalidCharge))
  assert_eq(ledger_usage(ledger), before)
  let writer = @encode.writer(continuation_test_wire().length() - 1, 100, 10)
  assert_eq(
    write_ledger_continuation_state(
      continuation_test_decode(continuation_test_wire()).unwrap(),
      writer,
    ),
    Err(Encoding),
  )
  assert_eq(ledger_usage(ledger), before)
}

///|
test "ledger continuation checks imported currentness before final snapshot and pristine restore" {
  let ledger = create_ledger(continuation_test_limits()).unwrap()
  let original = capture_quiescent_ledger_state(ledger).unwrap()
  let mode = Ref(1)
  let nested : Ref[Result[Unit, LedgerContinuationIssue]?] = Ref(None)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if mode.val == 1 {
        mode.val = 0
        charge_planning(ledger, 1).unwrap()
      } else if mode.val == 2 {
        mode.val = 0
        nested.val = Some(restore_quiescent_ledger_state(ledger, original))
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_eq(restore_quiescent_ledger_state(ledger, original), Err(NotPristine))
  assert_eq(ledger_usage(ledger).planning_work, 1)
  let saved = capture_quiescent_ledger_state(ledger).unwrap()
  assert_eq(saved.state.usage.planning_work, 1)
  let pristine = create_ledger(continuation_test_limits()).unwrap()
  ledger.usage = pristine.usage
  mode.val = 2
  assert_eq(
    restore_quiescent_ledger_state(ledger, original),
    Err(AlreadyRestored),
  )
  assert_true(nested.val is Some(Ok(_)))
  assert_true(ledger.continuation_restored)
}
