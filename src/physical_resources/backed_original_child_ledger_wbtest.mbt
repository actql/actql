///|
// Nominal Resource accounting only. Ref originals and final owner-ACK calls
// are physical stand-ins; no Native arena, FD, VM or worker is created here.
fn backed_original_child_fixture() -> (
  Ledger,
  BackedExecutionLiveAccess[Ref[Int], Ref[Int], Ref[Int]],
  BackedExecutionLiveProjection[Ref[Int], Ref[Int], Ref[Int]],
  Ref[Int],
) {
  let (parent, _, _, provider, region) = backed_test_region()
  let child = Ref(2)
  let ticket = backed_read_test_ticket(region, provider, child)
  let read = borrow_backed_execution_read_use(region, provider, child, ticket).unwrap()
  let runtime = Ref(3)
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read, runtime,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, runtime).unwrap()
  (parent, access, projection, runtime)
}

///|
test "backed original child starts the bootstrap census before workspace without parent re-reservation" {
  let (parent, _, projection, runtime) = backed_original_child_fixture()
  let before = ledger_usage(parent)
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(frame).unwrap()
  assert_true(take_imported_child_ledger(frame) is Err(Unavailable))
  let ledger = take_imported_original_child_ledger(frame).unwrap()
  assert_eq(ledger_limits(ledger), backed_test_limits())
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger.next_capacity_serial, Some(-1))
  assert_true(frame.wasm_capacity is None && frame.host_capacity is None)
  let bootstrap = reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = begin_original_ledger_inventory(ledger, bootstrap, 4, 0, 0).unwrap()
  let workspace = reserve_shared_capacity(ledger, 10L).unwrap()
  let origin = Ref(4)
  let descriptor = issue_recorded_original_ledger_descriptor(identity, origin).unwrap()
  let read = fund_original_read(ledger, origin, descriptor, 7L, 5L).unwrap()
  let pair = issue_original_read_workspace_binding(read, origin, workspace).unwrap()
  assert_true(original_read_workspace_binding_current(pair, origin, workspace))
  assert_eq(ledger_usage(parent), before)
  report_imported_child_ledger(frame).unwrap()
  assert_true(projection.access.unwrap().ticket.unwrap().live_usage_reported)
  assert_eq(
    ledger_usage(parent).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  assert_eq(
    ledger_usage(parent).reserved_retention_bytes,
    before.reserved_retention_bytes,
  )
  // Neither the inherited view nor a successful report releases physical bytes.
  close_shared_capacity(workspace).unwrap()
  settle_shared_capacity(workspace).unwrap()
  stop_funded_read(read).unwrap()
  settle_funded_read(read, true).unwrap()
  retire_original_read_workspace_binding(pair, origin, workspace).unwrap()
  assert_true(finish_funded_read_inventory(read, origin, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  report_imported_child_ledger(frame).unwrap()
  assert_eq(
    ledger_usage(parent).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
}

///|
test "backed original child rejects copied projection frame foreign runtime and repeated take" {
  let (parent, _, projection, runtime) = backed_original_child_fixture()
  let before = ledger_usage(parent)
  assert_true(
    prepare_backed_original_child_ledger({ ..projection, }, runtime)
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_backed_original_child_ledger(projection, Ref(3))
    is Err(ForeignOriginal),
  )
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  assert_true(
    prepare_backed_original_child_ledger(projection, runtime)
    is Err(AlreadyConsumed),
  )
  assert_true(start_imported_child_ledger({ ..frame, }) is Err(ForeignOriginal))
  start_imported_child_ledger(frame).unwrap()
  assert_true(start_imported_child_ledger(frame) is Err(AlreadyConsumed))
  assert_true(
    take_imported_original_child_ledger({ ..frame, }) is Err(ForeignOriginal),
  )
  take_imported_original_child_ledger(frame).unwrap() |> ignore
  assert_true(
    take_imported_original_child_ledger(frame) is Err(AlreadyConsumed),
  )
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed original child rechecks prior reserved usage after preparation without resetting it" {
  let (parent, _, projection, runtime) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  let before = ledger_usage(parent)
  report_backed_execution_live_child(projection, runtime, {
    ..backed_live_test_zero_usage(),
    reserved_execution_bytes: 1L,
  }).unwrap()
  assert_true(start_imported_child_ledger(frame) is Err(Unavailable))
  assert_true(frame.attempted && frame.ledger is None)
  assert_true(start_imported_child_ledger(frame) is Err(AlreadyConsumed))
  assert_true(take_imported_original_child_ledger(frame) is Err(Unavailable))
  assert_true(
    prepare_backed_original_child_ledger(projection, runtime)
    is Err(AlreadyConsumed),
  )
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed original child closing rejects new reservations and retains original cleanup reporting" {
  let (parent, _, projection, runtime) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(frame).unwrap()
  let ledger = take_imported_original_child_ledger(frame).unwrap()
  let capacity = reserve_shared_capacity(ledger, 8L).unwrap()
  let before = ledger_usage(parent)
  stop_imported_child_ledger(frame).unwrap()
  assert_eq(
    backed_execution_live_state(projection, runtime).unwrap(),
    LiveClosing,
  )
  assert_true(reserve_capacity(ledger, 1L, 1L) is Err(ClosedReservation))
  close_shared_capacity(capacity).unwrap()
  settle_shared_capacity(capacity).unwrap()
  report_imported_child_ledger(frame).unwrap()
  assert_eq(ledger_usage(parent), before)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  // Logical stop is not the physical-owner ACK; all parent obligations remain.
  assert_true(projection.access is Some(_))
}

///|
test "backed original child owner retirement clears captured parent graph without refund" {
  let (parent, access, projection, runtime) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(frame).unwrap()
  let ledger = take_imported_original_child_ledger(frame).unwrap()
  let before = ledger_usage(parent)
  stop_imported_child_ledger(frame).unwrap()
  retire_backed_execution_live_child_after_owner_ack(access, runtime).unwrap()
  assert_true(access.child_origin is None && projection.access is None)
  assert_true(frame.origin.ledger is None && frame.origin.unavailable)
  assert_eq((frame.origin.current)(1L), -42)
  assert_eq((frame.origin.admit)(1L), -42)
  assert_eq((frame.origin.limit)(1L, 0), -42L)
  assert_eq((frame.origin.capacity)(1L, 0), -42L)
  assert_true(reserve_capacity(ledger, 1L, 1L) is Err(ForeignOwner))
  assert_true(report_imported_child_ledger(frame) is Err(Unavailable))
  assert_true(frame.pending_report is Some(_))
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed original child keeps a prepared frame unavailable after parent retirement" {
  let (parent, access, projection, runtime) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  let before = ledger_usage(parent)
  retire_backed_execution_live_child_after_owner_ack(access, runtime).unwrap()
  // Existing start refuses a stopping original before admission. Retirement
  // does not pretend this unstarted frame attempted another parent admission.
  assert_true(start_imported_child_ledger(frame) is Err(AlreadyConsumed))
  assert_true(
    !frame.attempted && frame.ledger is None && frame.origin.unavailable,
  )
  assert_true(start_imported_child_ledger(frame) is Err(AlreadyConsumed))
  assert_true(
    take_imported_original_child_ledger(frame) is Err(AlreadyConsumed),
  )
  assert_true(!frame.taken)
  assert_eq(ledger_usage(parent), before)
}

///|
test "backed original child cannot reinterpret the old imported VM Host capacities" {
  let (frame, _, _, _, _) = imported_child_fixture()
  start_imported_child_ledger(frame).unwrap()
  assert_true(take_imported_original_child_ledger(frame) is Err(Unavailable))
  let (ledger, vm, host) = take_imported_child_ledger(frame).unwrap()
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 12L)
  assert_eq(shared_capacity_usage(vm).capacity, 8L)
  assert_eq(shared_capacity_usage(host).capacity, 4L)
}

///|
test "backed original child enforces inherited bytes and reports actual attempts only once" {
  let (parent, access, projection, runtime) = backed_original_child_fixture()
  let frame = prepare_backed_original_child_ledger(projection, runtime).unwrap()
  start_imported_child_ledger(frame).unwrap()
  let ledger = take_imported_original_child_ledger(frame).unwrap()
  let before = ledger_usage(parent)
  assert_true(reserve_capacity(ledger, 13L, 0L) is Err(RetentionLimit))
  assert_true(reserve_shared_capacity(ledger, 21L) is Err(ExecutionLimit))
  assert_eq(ledger_usage(ledger).attempts, 0)
  let reservation = reserve_attempt(ledger, 0L, 0L, 20L).unwrap()
  assert_true(reserve_shared_capacity(ledger, 1L) is Err(ExecutionLimit))
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger_usage(ledger).reserved_attempts, 1)
  consume_reserved_attempt(ledger, reservation).unwrap()
  report_imported_child_ledger(frame).unwrap()
  let reported = ledger_usage(parent)
  assert_eq(reported, {
    ..before,
    attempts: before.attempts + 1,
    live_reservations: before.live_reservations + 1,
  })
  report_imported_child_ledger(frame).unwrap()
  assert_eq(ledger_usage(parent), reported)
  stop_imported_child_ledger(frame).unwrap()
  settle_reservation(ledger, reservation).unwrap()
  report_imported_child_ledger(frame).unwrap()
  assert_eq(ledger_usage(parent), {
    ..reported,
    live_reservations: reported.live_reservations - 1,
  })
  assert_true(access.read_use.unwrap().live_access_pending)
  assert_true(access.ticket.unwrap().logical.unwrap().reservation.open)
}
