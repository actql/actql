///|
// Real Resource originals and canonical Request admission. The fixed VM
// observation and after-owner-ACK below are explicit nominal physical ports,
// not a Python VM, installed permission, provider or physical Store receipt.
fn platform_vm_request_fixture() -> (
  Ledger,
  SharedCapacity,
  PlatformVMWorkingCapacity,
  BackedExecutionRegion[Ref[Int], Ref[Int]],
  BackedExecutionDelegation[Ref[Int], Ref[Int]],
  BackedExecutionReadUse[Ref[Int], Ref[Int]],
  BackedExecutionLiveAccess[Ref[Int], Ref[Int], Ref[Int]],
  BackedPreparationAdmission[Ref[Int]],
  Ref[Int],
  Ref[Int],
  Ref[Int],
) {
  let root = create_ledger({
    planning_work: 64,
    attempts: 16,
    holdings: 8,
    transfer_bytes: 128L,
    retained_bytes: 1048576L,
    execution_bytes: 65536L + 4096L,
  }).unwrap()
  let capacity = reserve_shared_capacity(root, 65536L).unwrap()
  let vm = bind_platform_vm_capacity_original(1L, root, capacity, (_, ordinal) => {
    if ordinal == 0 {
      0L
    } else if ordinal == 1 {
      65536L
    } else {
      -42L
    }
  }).unwrap()
  let working = reserve_platform_vm_working_capacity(vm, 4096L, 0L).unwrap()
  let provider = Ref(1)
  let child = Ref(2)
  let input = Ref(3)
  let region : BackedExecutionRegion[Ref[Int], Ref[Int]] = issue_platform_vm_preparation_region(
    working, provider,
  ).unwrap()
  let ticket = reserve_backed_execution_delegation(
    region,
    provider,
    child,
    { offset: 0L, length: 4096L, payload_offset: 0L, payload_length: 4096L, },
    ExclusiveWrite,
    {
      planning_work: 32,
      attempts: 4,
      holdings: 4,
      transfer_bytes: 64L,
      // Unused ceilings are DATA. They exceed the original whole VM and are
      // not claimed before the actual canonical constructors need bytes.
      retained_bytes: 1048576L,
      execution_bytes: 1048576L,
    },
    4096L,
    4096L,
  ).unwrap()
  let read = borrow_backed_execution_read_use(region, provider, child, ticket).unwrap()
  let access = issue_backed_execution_live_access(
    region, provider, child, ticket, read, input,
  ).unwrap()
  let projection = admit_backed_execution_live_child(access, input).unwrap()
  let initial = prepare_backed_preparation_admission(projection, input).unwrap()
  (
    root, capacity, working, region, ticket, read, access, initial, provider, child,
    input,
  )
}

///|
fn finish_platform_vm_request_fixture(
  working : PlatformVMWorkingCapacity,
  region : BackedExecutionRegion[Ref[Int], Ref[Int]],
  ticket : BackedExecutionDelegation[Ref[Int], Ref[Int]],
  read : BackedExecutionReadUse[Ref[Int], Ref[Int]],
  access : BackedExecutionLiveAccess[Ref[Int], Ref[Int], Ref[Int]],
  initial : BackedPreparationAdmission[Ref[Int]],
  provider : Ref[Int],
  child : Ref[Int],
  input : Ref[Int],
) -> Unit raise {
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = frame.ledger.unwrap()
  assert_true(continuation_quiescent(ledger))
  let usage = ledger_usage(ledger)
  stop_imported_child_ledger(frame).unwrap()
  report_imported_child_ledger(frame).unwrap()
  assert_true(cleanup_backed_preparation_admission(initial) is Err(Unavailable))
  // Explicit original-owner retirement port, not an inferred physical ACK.
  retire_backed_execution_live_child_after_owner_ack(access, input).unwrap()
  cleanup_backed_preparation_admission(initial).unwrap()
  return_backed_execution_read_use_after_owner_ack(
    region, provider, child, ticket, read,
  ).unwrap()
  settle_backed_execution_after_owner_ack(
    region,
    provider,
    child,
    ticket,
    Some(usage),
  ).unwrap()
  assert_true(close_backed_execution_region(region, provider).unwrap())
  close_platform_vm_working_capacity_after_cleanup(working).unwrap()
}

///|
test "platform Request admission grows canonical reservation and resize before same ledger mutation" {
  let (
    root,
    capacity,
    working,
    region,
    ticket,
    read,
    access,
    initial,
    provider,
    child,
    input,
  ) = platform_vm_request_fixture()
  assert_eq(shared_capacity_usage(capacity).allocated, 4096L)
  let repeated : Result[
    BackedExecutionRegion[Ref[Int], Ref[Int]],
    BackedExecutionIssue,
  ] = issue_platform_vm_preparation_region(working, provider)
  assert_true(repeated is Err(DuplicateChild))
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  assert_true(physical_equal(ledger, frame.ledger.unwrap()))
  let prefix : PreparationCapacity[Ref[Int], Unit] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    128L,
    32L,
    max_borrowers=4,
  ).unwrap()
  let scratch = reserve_capacity(ledger, 20L, 30L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 4096L + 148L + 62L)
  let before = ledger_usage(ledger)
  let serial = ledger.next_capacity_serial
  let held = shared_capacity_usage(capacity).allocated
  // Logical policy permits this size, but the SAME VM/input coexistence does
  // not. Refusal changes neither serial, ledger usage nor the existing claim.
  assert_true(reserve_capacity(ledger, 65536L, 1L) is Err(RetentionLimit))
  assert_eq(ledger_usage(ledger), before)
  assert_eq(ledger.next_capacity_serial, serial)
  assert_eq(shared_capacity_usage(capacity).allocated, held)
  resize_capacity_reservation(ledger, prefix.reservation, 512L, 128L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 4096L + 532L + 158L)
  let description = backed_execution_delegation_description(
    region, provider, child, ticket,
  ).unwrap()
  assert_eq(description.0.payload_length, 4096L + 532L + 158L)
  assert_eq(description.2.retained_bytes, 1048576L)
  report_imported_child_ledger(frame).unwrap()
  // Cumulative reports cannot replace a missing pre-construction claim.
  assert_true(
    report_backed_execution_delegation(region, provider, child, ticket, {
      ..ledger_usage(ledger),
      reserved_retention_bytes: 600L,
      peak_retention_bytes: 600L,
    })
    is Err(Resource(InvalidCharge)),
  )
  settle_capacity(ledger, scratch).unwrap()
  assert_true(abort_preparation_capacity_after_cleanup(prefix, input).unwrap())
  finish_platform_vm_request_fixture(
    working, region, ticket, read, access, initial, provider, child, input,
  )
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
  assert_eq(ledger_usage(root).reserved_execution_bytes, 65536L)
}

///|
test "platform Request attempt growth uses same demand claim and keeps earlier peak through stop" {
  let (
    _,
    capacity,
    working,
    region,
    ticket,
    read,
    access,
    initial,
    provider,
    child,
    input,
  ) = platform_vm_request_fixture()
  let frame = backed_preparation_original_frame(initial, input).unwrap()
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  let attempt = reserve_attempt(ledger, 0L, 256L, 128L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 4096L + 256L + 128L)
  grow_execution_reservation_capacity(ledger, attempt, 512L, 256L).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, 4096L + 512L + 256L)
  let snapshot = ledger_usage(ledger)
  let held = shared_capacity_usage(capacity).allocated
  assert_true(
    grow_execution_reservation_capacity(ledger, attempt, 65536L, 256L)
    is Err(RetentionLimit),
  )
  assert_eq(ledger_usage(ledger), snapshot)
  assert_eq(shared_capacity_usage(capacity).allocated, held)
  stop_imported_child_ledger(frame).unwrap()
  assert_true(reserve_capacity(ledger, 0L, 0L) is Err(ClosedReservation))
  reduce_execution_reservation(ledger, attempt, 0L).unwrap()
  settle_reservation(ledger, attempt).unwrap()
  assert_eq(shared_capacity_usage(capacity).allocated, held)
  finish_platform_vm_request_fixture(
    working, region, ticket, read, access, initial, provider, child, input,
  )
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
}

///|
test "platform Request original admission and body borrowers retain failed cleanup until original returns" {
  let (
    _,
    capacity,
    working,
    region,
    ticket,
    read,
    access,
    initial,
    provider,
    child,
    input,
  ) = platform_vm_request_fixture()
  assert_true(
    prepare_backed_preparation_admission(access.projection.unwrap(), Ref(3))
    is Err(ForeignOriginal),
  )
  let ledger = start_backed_preparation_admission(initial, input).unwrap()
  let prefix : PreparationCapacity[Ref[Int], Ref[Int]] = reserve_preparation_capacity_inventory(
    ledger,
    input,
    128L,
    32L,
    max_borrowers=4,
  ).unwrap()
  let body = Ref(4)
  complete_preparation_capacity(prefix, input, body, 64L, 0L).unwrap()
  let borrow = borrow_preparation_capacity(prefix).unwrap()
  let held = shared_capacity_usage(capacity).allocated
  assert_false(retire_preparation_capacity(prefix).unwrap())
  assert_true(cleanup_backed_preparation_admission(initial) is Err(Unavailable))
  assert_eq(shared_capacity_usage(capacity).allocated, held)
  return_preparation_capacity_borrow(borrow).unwrap() |> ignore
  assert_true(retire_preparation_capacity(prefix).unwrap())
  finish_platform_vm_request_fixture(
    working, region, ticket, read, access, initial, provider, child, input,
  )
  assert_eq(shared_capacity_usage(capacity).allocated, 0L)
}
