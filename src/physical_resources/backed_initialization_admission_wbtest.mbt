///|
// Nominal accounting/lifetime cases only. The existing after-owner-ACK call
// is a physical stand-in here, not an actual Native C-context acknowledgement.
test "backed initialization binds original input before its single start and waits for owner retirement" {
  let (parent, access, projection, input) = backed_original_child_fixture()
  let before = ledger_usage(parent)
  assert_true(
    prepare_backed_initialization_admission({ ..projection, }, input)
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_backed_initialization_admission(projection, Ref(3))
    is Err(ForeignOriginal),
  )
  let initial = prepare_backed_initialization_admission(projection, input).unwrap()
  let frame = backed_initialization_original_frame(initial, input).unwrap()
  assert_false(frame.attempted || frame.taken)
  assert_false(backed_initialization_ledger_published(initial, input).unwrap())
  assert_true(
    check_backed_initialization_input({ ..initial, }, input)
    is Err(ForeignOriginal),
  )
  assert_true(
    check_backed_initialization_input(initial, Ref(3)) is Err(ForeignOriginal),
  )
  assert_true(
    prepare_backed_initialization_admission(projection, input)
    is Err(AlreadyConsumed),
  )
  let ledger = start_backed_initialization_admission(initial).unwrap()
  assert_true(backed_initialization_ledger_published(initial, input).unwrap())
  assert_true(physical_equal(frame.ledger.unwrap(), ledger))
  assert_true(
    start_backed_initialization_admission(initial) is Err(AlreadyConsumed),
  )
  assert_true(
    take_backed_initialization_admission(initial, input) is Err(Unavailable),
  )
  // Explicit accounting-fixture quantities, not a Native/Source recipe. The
  // actual physical issuer must supply its own complete original census.
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap() |> ignore
  assert_true(
    physical_equal(
      take_backed_initialization_admission(initial, input).unwrap(),
      ledger,
    ),
  )
  assert_true(
    take_backed_initialization_admission(initial, input) is Err(AlreadyConsumed),
  )
  let body : PreparationCapacity[Ref[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    0L,
    0L,
    max_borrowers=4,
  ).unwrap()
  abort_preparation_capacity_after_cleanup(body, input).unwrap() |> ignore
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_true(
    cleanup_backed_initialization_admission(initial) is Err(Unavailable),
  )
  assert_true(initial.input is Some(_))
  assert_true(projection.access is Some(_))
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_initialization_admission(initial).unwrap()
  cleanup_backed_initialization_admission(initial).unwrap()
  assert_true(initial.input is None && initial.cleaned)
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed initialization unstarted cleanup never fabricates a Ledger or a zero report" {
  let (parent, access, projection, input) = backed_original_child_fixture()
  let before = ledger_usage(parent)
  let initial = prepare_backed_initialization_admission(projection, input).unwrap()
  let frame = backed_initialization_original_frame(initial, input).unwrap()
  assert_true(
    cleanup_backed_initialization_admission(initial) is Err(Unavailable),
  )
  assert_false(backed_initialization_ledger_published(initial, input).unwrap())
  assert_false(frame.attempted || frame.taken)
  assert_true(frame.ledger is None && frame.stop_attempted)
  assert_true(report_imported_child_ledger(frame) is Err(Unavailable))
  assert_true(initial.input is Some(_))
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_initialization_admission(initial).unwrap()
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed initialization cannot reuse an already issued Read frame" {
  let (_, _, projection, input) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, input).unwrap()
  start_imported_child_ledger(frame).unwrap()
  take_imported_original_child_ledger(frame).unwrap() |> ignore
  assert_true(
    prepare_backed_initialization_admission(projection, input)
    is Err(AlreadyConsumed),
  )
}
