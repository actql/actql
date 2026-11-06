///|
// Actual portable Resource/capacity/adoption/lease ownership. These existing
// nominal region ports and after-owner-ACK calls are explicit physical stand-
// ins, not a real VM, Native context, Source, Run or ordinary funding claim.
test "backed Request preparation transfers same child and two holders without Node or Host retirement" {
  let (parent, access, projection, input) = backed_original_child_fixture()
  let before = ledger_usage(parent)
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  assert_true(physical_equal(frame.ledger.unwrap(), ledger))
  assert_eq(
    backed_preparation_limits(initial, input).unwrap(),
    backed_test_limits(),
  )
  let capacity : PreparationCapacity[Ref[Int], Ref[Int]] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    6L,
    4L,
    max_borrowers=4,
  ).unwrap()
  let body = Ref(4)
  complete_preparation_capacity(capacity, input, body, 4L, 0L).unwrap()
  let (run, same, retirement, run_holder) = adopt_backed_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  assert_true(physical_equal(ledger, same))
  assert_true(physical_equal(run.child, frame))
  check_backed_prepared_run_admission(run, body, same).unwrap()
  assert_true(
    adopt_backed_preparation_admission(initial, input, capacity, body)
    is Err(AlreadyConsumed),
  )
  assert_true(
    cleanup_backed_preparation_admission(initial) is Err(AlreadyConsumed),
  )
  assert_true(release_backed_preparation_holder(run) is Err(Unavailable))
  assert_false(retire_transferred_preparation(retirement).unwrap())
  assert_false(return_preparation_body_borrow(run_holder).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 4L)
  assert_true(release_backed_preparation_holder(run).unwrap())
  assert_true(retire_transferred_preparation(retirement).unwrap())
  assert_true(cleanup_backed_prepared_run_admission(run) is Err(Unavailable))
  assert_false(run.cleaned)
  assert_true(projection.access is Some(_))
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_prepared_run_admission(run).unwrap()
  cleanup_backed_prepared_run_admission(run).unwrap()
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed Request preparation rejects copied foreign and stopped originals before holder escape" {
  let (_, access, projection, input) = backed_original_child_fixture()
  assert_true(
    prepare_backed_preparation_admission({ ..projection, }, input)
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_backed_preparation_admission(projection, Ref(3))
    is Err(ForeignOriginal),
  )
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  assert_true(
    prepare_backed_preparation_admission(projection, input)
    is Err(AlreadyConsumed),
  )
  assert_true(
    check_backed_preparation_input({ ..initial, }, input)
    is Err(ForeignOriginal),
  )
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  assert_true(
    start_backed_preparation_admission(initial, input) is Err(AlreadyConsumed),
  )
  let capacity : PreparationCapacity[Ref[Int], Ref[Int]] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    6L,
    4L,
    max_borrowers=4,
  ).unwrap()
  let body = Ref(4)
  complete_preparation_capacity(capacity, input, body, 4L, 0L).unwrap()
  let before = preparation_capacity_accounting(capacity)
  assert_true(
    adopt_backed_preparation_admission(initial, Ref(3), capacity, body)
    is Err(ForeignOriginal),
  )
  assert_true(
    adopt_backed_preparation_admission(initial, input, capacity, Ref(4))
    is Err(ForeignOriginal),
  )
  assert_eq(preparation_capacity_accounting(capacity), before)
  stop_backed_execution_live_child(access, input).unwrap()
  assert_true(
    adopt_backed_preparation_admission(initial, input, capacity, body) is Err(_),
  )
  assert_eq(capacity.borrowers, 0)
  assert_true(capacity.phase == Ready)
  assert_false(initial.transferred)
  assert_true(retire_preparation_capacity(capacity).unwrap())
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_preparation_admission(initial).unwrap()
}

///|
test "backed Request failed constructor retains same input capacity and physical cleanup until real return" {
  let (parent, access, projection, input) = backed_original_child_fixture()
  let before = ledger_usage(parent)
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  let capacity : PreparationCapacity[Ref[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    6L,
    4L,
    max_borrowers=4,
  ).unwrap()
  let original = Ref(4)
  let construction_input = reserve_preparation_construction_input(
    capacity, input, original, 6L, 4L,
  ).unwrap()
  assert_false(
    abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  assert_true(cleanup_backed_preparation_admission(initial) is Err(Unavailable))
  assert_true(
    preparation_body_borrow_value(construction_input) is Some(value) &&
    physical_equal(value, original),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 6L)
  assert_true(return_preparation_body_borrow(construction_input).unwrap())
  assert_true(preparation_capacity_reservation_retired(capacity))
  assert_true(cleanup_backed_preparation_admission(initial) is Err(Unavailable))
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_preparation_admission(initial).unwrap()
  assert_true(initial.initial.cleaned)
  assert_eq(ledger_usage(parent), before)
}

///|
fn backed_prepared_operation_fixture() -> (
  BackedExecutionLiveAccess[Ref[Int], Ref[Int], Ref[Int]],
  Ref[Int],
  PreparedRunAdmission[Ref[Int]],
  Ref[Int],
  Ledger,
  ImportedChildLedger,
  PreparationRetirement,
  PreparationBodyBorrow[Ref[Int]],
) {
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
  let (admission, _, retirement, holder) = adopt_backed_preparation_admission(
    initial, input, capacity, body,
  ).unwrap()
  (
    access,
    input,
    backed_prepared_run_admission(admission),
    body,
    ledger,
    frame,
    retirement,
    holder,
  )
}

///|
test "backed prepared operation retains same control and constructor until actual retirement" {
  let (access, input, admission, body, ledger, frame, retirement, holder) = backed_prepared_operation_fixture()
  let (control, backing) = reserve_prepared_run_operation(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
    false,
    0L,
    2L,
    2L,
  ).unwrap()
  guard backing.unwrap() is Construction(construction) else {
    fail("constructor must retain its original byte reservation")
  }
  let before = ledger_usage(ledger)
  assert_eq(before.reserved_retention_bytes, 7L)
  begin_prepared_run_operation_construction(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    Construction(construction),
    3L,
  ).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 4L)
  complete_prepared_run_operation_construction(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    Construction(construction),
  ).unwrap()
  // Completion returns only the original scratch, not the retained output.
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 7L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 3L)
  settle_capacity(ledger, construction).unwrap()
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 5L)
  settle_capacity(ledger, control).unwrap()
  assert_false(retire_transferred_preparation(retirement).unwrap())
  return_preparation_body_borrow(holder).unwrap() |> ignore
  release_prepared_run_holder(admission).unwrap() |> ignore
  assert_true(retire_transferred_preparation(retirement).unwrap())
  assert_true(cleanup_prepared_run_admission(admission) is Err(Unavailable))
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_prepared_run_admission(admission).unwrap()
}

///|
test "backed prepared operation preserves original consumer refusal and post-consumer current fence" {
  let (access, input, admission, body, ledger, _, _, _) = backed_prepared_operation_fixture()
  let before = ledger_usage(ledger)
  assert_true(
    reserve_prepared_run_operation(
      admission,
      body,
      ledger,
      () => Err("original-consumer"),
      None,
      1L,
      1L,
      false,
      0L,
      2L,
      2L,
    )
    is Err(Original("original-consumer")),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_true(
    reserve_prepared_run_operation(
      admission,
      body,
      ledger,
      () => {
        stop_backed_execution_live_child(access, input).unwrap()
        (Ok(()) : Result[Unit, Unit])
      },
      None,
      1L,
      1L,
      false,
      0L,
      2L,
      2L,
    )
    is Err(Admission(_)),
  )
  assert_eq(ledger_usage(ledger), before)
  // Stopping that physical original is not ACK and cannot dispose its holders.
  assert_true(cleanup_prepared_run_admission(admission) is Err(Unavailable))
}

///|
test "original prepared response projection refuses foreign and closed physical tokens without returning other bytes" {
  let (access, input, admission, body, ledger, frame, retirement, holder) = backed_prepared_operation_fixture()
  let (control, backing) = reserve_prepared_run_operation(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    None,
    1L,
    1L,
    true,
    2L,
    2L,
    6L,
  ).unwrap()
  guard backing.unwrap() is Physical(reservation) else {
    fail("Expected original physical reservation")
  }
  consume_reserved_attempt(ledger, reservation).unwrap()
  charge_transfer(ledger, reservation, 1L).unwrap()
  let before = ledger_usage(ledger)
  // A different supplied Ledger cannot replace the admitted original.
  let foreign = create_ledger(backed_test_limits()).unwrap()
  assert_true(
    complete_prepared_run_operation_response_projection(
      admission,
      body,
      foreign,
      () => (Ok(()) : Result[Unit, Unit]),
      Physical(reservation),
    )
    is Err(_),
  )
  assert_eq(ledger_usage(ledger), before)
  let foreign_token = reserve_attempt(foreign, 1L, 1L, 2L).unwrap()
  let foreign_before = ledger_usage(foreign)
  assert_true(
    complete_prepared_run_operation_response_projection(
      admission,
      body,
      ledger,
      () => (Ok(()) : Result[Unit, Unit]),
      Physical(foreign_token),
    )
    is Err(Control(ForeignOwner)),
  )
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger_usage(foreign), foreign_before)
  settle_reservation(foreign, foreign_token).unwrap()
  complete_prepared_run_operation_response_projection(
    admission,
    body,
    ledger,
    () => (Ok(()) : Result[Unit, Unit]),
    Physical(reservation),
  ).unwrap()
  assert_eq(ledger_usage(ledger), {
    ..before,
    reserved_execution_bytes: before.reserved_execution_bytes - 4L,
  })
  settle_reservation(ledger, reservation).unwrap()
  let settled = ledger_usage(ledger)
  assert_true(
    complete_prepared_run_operation_response_projection(
      admission,
      body,
      ledger,
      () => (Ok(()) : Result[Unit, Unit]),
      Physical(reservation),
    )
    is Err(Control(ClosedReservation)),
  )
  assert_eq(ledger_usage(ledger), settled)
  settle_capacity(ledger, control).unwrap()
  assert_false(retire_transferred_preparation(retirement).unwrap())
  return_preparation_body_borrow(holder).unwrap() |> ignore
  release_prepared_run_holder(admission).unwrap() |> ignore
  assert_true(retire_transferred_preparation(retirement).unwrap())
  assert_true(cleanup_prepared_run_admission(admission) is Err(Unavailable))
  report_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_prepared_run_admission(admission).unwrap()
}
