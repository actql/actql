///|
test "nested unavailable currentness dominates an outer positive imported observation" {
  for lost in [-1, -41] {
    // Same private callback fixture, not a VM, channel or physical child.
    let (value, _, _, _, _) = imported_child_fixture()
    start_imported_child_ledger(value).unwrap()
    let (ledger, _, _) = take_imported_child_ledger(value).unwrap()
    let origin = ledger.imported_child.unwrap()
    let phase = Ref(0)
    let nested_refused = Ref(false)
    origin.current = _ => {
      if phase.val == 0 {
        phase.val = 1
        nested_refused.val = charge_planning(ledger, 0)
          is Err(ChildFundingUnavailable)
        phase.val = 2
        0
      } else if phase.val == 1 {
        lost
      } else {
        0
      }
    }
    let usage = ledger_usage(ledger)
    let serials = (
      ledger.next_attempt_serial,
      ledger.next_capacity_serial,
      ledger.next_holding_serial,
    )
    let attempted = reserve_attempt(ledger, 0L, 0L, 0L)
    assert_true(nested_refused.val)
    assert_true(origin.unavailable)
    assert_true(
      attempted is Err(ChildFundingUnavailable),
      msg="a stale positive outer callback cannot restore lost funding",
    )
    assert_eq(ledger_usage(ledger), usage)
    assert_eq(
      (
        ledger.next_attempt_serial,
        ledger.next_capacity_serial,
        ledger.next_holding_serial,
      ),
      serials,
    )
    assert_true(
      reserve_attempt(ledger, 0L, 0L, 0L) is Err(ChildFundingUnavailable),
    )
    assert_eq(ledger_usage(ledger), usage)
    assert_eq(phase.val, 2)
  }
}

///|
test "stopping refuses an unused trusted Start but preserves original post-use accounting" {
  let (value, current, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(value).unwrap()
  let (ledger, _, _) = take_imported_child_ledger(value).unwrap()
  let started = reserve_attempt(ledger, 3L, 0L, 0L).unwrap()
  consume_reserved_attempt(ledger, started).unwrap()
  let unused = reserve_attempt(ledger, 0L, 0L, 0L).unwrap()
  current.val = 1
  let before = ledger_usage(ledger)
  assert_eq(consume_reserved_attempt(ledger, unused), Err(ClosedReservation))
  assert_eq(ledger_usage(ledger), before)
  assert_false(unused.attempt_started)
  // The transport may report a prior use after stop. This is final accounting,
  // not another before-use admission or a reason to refund the original Start.
  charge_transfer(ledger, started, 1L).unwrap()
  mark_transfer_uncertain(ledger, started, 1L).unwrap()
  let accounted = ledger_usage(ledger)
  assert_eq(accounted.attempts, 1)
  assert_eq(accounted.transferred_bytes, 1L)
  assert_eq(accounted.uncertain_transfer_bytes, 1L)
  settle_reservation(ledger, started).unwrap()
  settle_reservation(ledger, unused).unwrap()
  assert_eq(ledger_usage(ledger).attempts, 1)
  assert_eq(ledger_usage(ledger).reserved_attempts, 0)
}
