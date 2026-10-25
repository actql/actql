///|
// These are private original-port controls, not physical supply or ACKs.
test "cleanup DATA relocation keeps original Ledger and exact charges" {
  let (frame, current, _, reports, _) = imported_child_fixture()
  start_imported_child_ledger(frame).unwrap()
  let (ledger, _, _) = take_imported_child_ledger(frame).unwrap()
  let reservation = reserve_capacity(ledger, 2L, 3L).unwrap()
  settle_capacity(ledger, reservation).unwrap()
  assert_true(relocate_imported_child_cleanup_usage(frame) is Err(Unavailable))
  stop_imported_child_ledger(frame).unwrap()
  current.val = 1
  // Exact fixture DATA exercises every nested immutable quantity record.
  ledger.quantity_limits = Some({
    tokens: 17L,
    cost_units: 19L,
    duration_ms: 23L,
  })
  ledger.quantity_usage = {
    reserved: { tokens: 2L, cost_units: 3L, duration_ms: 5L, },
    uncertain: { tokens: 7L, cost_units: 11L, duration_ms: 13L, },
    consumed: { tokens: 1L, cost_units: 1L, duration_ms: 1L, },
  }
  let old_usage = ledger_usage(ledger)
  let old_quantities = quantity_usage(ledger)
  let old_limits = ledger.quantity_limits.unwrap()
  let serial = ledger.next_capacity_serial
  let origin = ledger.imported_child.unwrap()
  relocate_imported_child_cleanup_usage(frame).unwrap()
  assert_true(physical_equal(frame.ledger.unwrap(), ledger))
  assert_true(physical_equal(ledger.imported_child.unwrap(), origin))
  assert_eq(ledger_usage(ledger), old_usage)
  assert_false(physical_equal(ledger_usage(ledger), old_usage))
  assert_eq(quantity_usage(ledger), old_quantities)
  assert_false(physical_equal(quantity_usage(ledger), old_quantities))
  assert_false(
    physical_equal(quantity_usage(ledger).reserved, old_quantities.reserved),
  )
  assert_false(
    physical_equal(quantity_usage(ledger).uncertain, old_quantities.uncertain),
  )
  assert_false(
    physical_equal(quantity_usage(ledger).consumed, old_quantities.consumed),
  )
  assert_eq(ledger.quantity_limits.unwrap(), old_limits)
  assert_false(physical_equal(ledger.quantity_limits.unwrap(), old_limits))
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(reports.val, 0)
  assert_true(reserve_capacity(ledger, 0L, 1L) is Err(ClosedReservation))
}

///|
test "cleanup relocation refuses copied retired and unconfirmed original controls" {
  let (frame, current, _, reports, _) = imported_child_fixture()
  start_imported_child_ledger(frame).unwrap()
  let (ledger, _, _) = take_imported_child_ledger(frame).unwrap()
  stop_imported_child_ledger(frame).unwrap()
  let copied = { ..frame, }
  assert_true(
    relocate_imported_child_cleanup_usage(copied) is Err(ForeignOriginal),
  )
  let usage = ledger_usage(ledger)
  current.val = -41
  assert_true(
    relocate_imported_child_cleanup_usage(frame)
    is Err(Resource(ChildFundingUnavailable)),
  )
  current.val = 0
  assert_true(
    relocate_imported_child_cleanup_usage(frame)
    is Err(Resource(ChildFundingUnavailable)),
  )
  assert_true(physical_equal(usage, ledger_usage(ledger)))
  assert_eq(reports.val, 0)
  let (uncertain, _, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(uncertain).unwrap()
  let _ = take_imported_child_ledger(uncertain).unwrap()
  uncertain.origin.stop = _ => -41
  assert_true(stop_imported_child_ledger(uncertain) is Err(Unknown))
  assert_true(relocate_imported_child_cleanup_usage(uncertain) is Err(Unknown))
}

///|
test "cleanup relocation retains failed report snapshot without resend" {
  let (frame, _, _, reports, _) = imported_child_fixture(report_code=-41)
  start_imported_child_ledger(frame).unwrap()
  let (ledger, _, _) = take_imported_child_ledger(frame).unwrap()
  assert_true(report_imported_child_ledger(frame) is Err(Unknown))
  let pending = frame.pending_report.unwrap()
  stop_imported_child_ledger(frame).unwrap()
  assert_true(relocate_imported_child_cleanup_usage(frame) is Err(Unknown))
  assert_true(physical_equal(frame.pending_report.unwrap(), pending))
  assert_true(physical_equal(ledger_usage(ledger), pending))
  assert_eq(reports.val, 1)
}
