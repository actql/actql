///|
// Existing portable accounting fixture, not an actual Node supplier or ACK.
test "original imported child check is read-only and refuses copied or fresh views" {
  let (parent, _, projection, runtime) = backed_original_child_fixture()
  let child = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(child).unwrap()
  let pending = child.ledger.unwrap()
  assert_true(
    check_imported_original_child_ledger(child, pending) is Err(Unavailable),
  )
  let ledger = take_imported_original_child_ledger(child).unwrap()
  let parent_before = ledger_usage(parent)
  let before = ledger_usage(ledger)
  check_imported_original_child_ledger(child, ledger).unwrap()
  let copied_child = { ..child, }
  let copied_ledger = { ..ledger, }
  let fresh = create_ledger(ledger_limits(ledger)).unwrap()
  assert_true(
    check_imported_original_child_ledger(copied_child, ledger)
    is Err(ForeignOriginal),
  )
  assert_true(
    check_imported_original_child_ledger(child, copied_ledger)
    is Err(ForeignOriginal),
  )
  assert_true(
    check_imported_original_child_ledger(child, fresh) is Err(ForeignOriginal),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(parent), parent_before)
  assert_true(!child.origin.stopping)
  assert_true(!projection.access.unwrap().ticket.unwrap().live_usage_reported)
}

///|
test "original imported child check cannot revive stopped or old VM capacity views" {
  let (parent, _, projection, runtime) = backed_original_child_fixture()
  let child = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(child).unwrap()
  let ledger = take_imported_original_child_ledger(child).unwrap()
  stop_imported_child_ledger(child).unwrap()
  let before = ledger_usage(ledger)
  let parent_before = ledger_usage(parent)
  assert_true(
    check_imported_original_child_ledger(child, ledger) is Err(Unavailable),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(parent), parent_before)
  let (old, _, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(old).unwrap()
  let (old_ledger, _, _) = take_imported_child_ledger(old).unwrap()
  let old_before = ledger_usage(old_ledger)
  assert_true(
    check_imported_original_child_ledger(old, old_ledger) is Err(Unavailable),
  )
  assert_eq(ledger_usage(old_ledger), old_before)
}
