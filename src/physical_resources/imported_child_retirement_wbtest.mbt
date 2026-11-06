///|
// Portable ownership fixtures only. A readiness observation is not an actual
// Native allocator close, backing release, physical ACK, or CLI acceptance.
test "original child retirement distinguishes never started from failed published take" {
  let (_, _, projection, input) = backed_original_child_fixture()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  stop_imported_child_ledger(frame).unwrap()
  assert_false(imported_child_retirement_readiness(frame).unwrap())
  assert_true(
    imported_child_retirement_readiness({ ..frame, }) is Err(ForeignOriginal),
  )

  let (_, _, projection, input) = backed_original_child_fixture()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  start_imported_child_ledger(frame).unwrap()
  assert_true(frame.ledger is Some(_))
  assert_false(frame.taken)
  stop_imported_child_ledger(frame).unwrap()
  assert_true(
    take_imported_original_child_ledger(frame) is Err(AlreadyConsumed),
  )
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  assert_false(frame.taken)
}

///|
test "original child retirement keeps failed unpublished start without retry or invented usage" {
  let (frame, _, admits, reports, _) = imported_child_fixture(admit_code=-41)
  assert_true(start_imported_child_ledger(frame) is Err(Unknown))
  assert_true(frame.attempted && frame.ledger is None && !frame.taken)
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  stop_imported_child_ledger(frame).unwrap()
  assert_false(imported_child_retirement_readiness(frame).unwrap())
  assert_true(start_imported_child_ledger(frame) is Err(AlreadyConsumed))
  assert_eq(admits.val, 1)
  assert_eq(reports.val, 0)
  assert_true(frame.original is Some(_))
}

///|
test "original child retirement does not confuse zero charged bytes with returned tokens" {
  let (_, _, projection, input) = backed_original_child_fixture()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  let zero = reserve_capacity(ledger, 0L, 0L).unwrap()
  stop_imported_child_ledger(frame).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  settle_capacity(ledger, zero).unwrap()
  assert_true(imported_child_retirement_readiness(frame).unwrap())
  assert_false(projection.retired_after_owner_ack)
}

///|
test "original child retirement keeps lost report and unknown debt on the same original" {
  let (_, _, projection, input) = backed_original_child_fixture()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  stop_imported_child_ledger(frame).unwrap()
  ledger.usage = { ..ledger.usage, uncertain_transfer_bytes: 1L, }
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  assert_eq(ledger_usage(ledger).uncertain_transfer_bytes, 1L)

  let (_, _, projection, input) = backed_original_child_fixture()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  start_backed_preparation_admission(initial, input).unwrap() |> ignore
  frame.origin.report = (_, _) => -41
  stop_imported_child_ledger(frame).unwrap()
  assert_true(imported_child_retirement_readiness(frame).unwrap())
  assert_true(report_imported_child_ledger(frame) is Err(Unknown))
  assert_true(imported_child_retirement_readiness(frame) is Err(Unknown))
  assert_true(frame.pending_report is Some(_))
  assert_false(projection.retired_after_owner_ack)
}

///|
test "original Request frame survives Run admission transfer and waits for both holders" {
  let (_, access, projection, input) = backed_original_child_fixture()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  let capacity : PreparationCapacity[Ref[Int], Ref[Int]] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    6L,
    4L,
    max_borrowers=4,
  ).unwrap()
  let body = Ref(4)
  complete_preparation_capacity(capacity, input, body, 4L, 0L).unwrap()
  let (run, same, retirement, holder) = adopt_backed_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_true(physical_equal(ledger, same))
  assert_true(physical_equal(frame, run.child))
  assert_true(
    backed_preparation_original_frame(initial, input) is Err(AlreadyConsumed),
  )
  stop_imported_child_ledger(frame).unwrap()
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_false(return_preparation_body_borrow(holder).unwrap())
  assert_true(imported_child_retirement_readiness(frame) is Err(Unavailable))
  assert_true(release_backed_preparation_holder(run).unwrap())
  assert_true(retire_transferred_preparation(retirement).unwrap())
  assert_true(imported_child_retirement_readiness(frame).unwrap())
  assert_true(cleanup_backed_prepared_run_admission(run) is Err(Unavailable))
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_prepared_run_admission(run).unwrap()
  assert_true(
    cleanup_backed_preparation_admission(initial) is Err(AlreadyConsumed),
  )
}
