///|
test "uncompleted preparation chooses its output without a second reservation or work refill" {
  let ledger = create_ledger({
    planning_work: 7,
    attempts: 8,
    holdings: 9,
    transfer_bytes: 1000L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let work = begin_preparation_phase_work(prefix, input, HeaderInspection, 10).unwrap()
  spend_preparation_phase_work(work, 3).unwrap()
  assert_eq(finish_preparation_phase_work(work).unwrap(), 3)
  let original_usage = ledger_usage(ledger)
  let next : PreparationCapacity[Array[Int], Array[String]] = continue_preparation_capacity(
    prefix, input,
  ).unwrap()
  assert_true(physical_equal(next.ledger, ledger))
  assert_true(physical_equal(next.reservation, prefix.reservation))
  assert_eq(next.max_borrowers, 1)
  assert_eq(next.last_work_phase, prefix.last_work_phase)
  assert_eq(ledger_usage(ledger), original_usage)
  assert_true(
    begin_preparation_phase_work(next, input, HeaderInspection, 10)
    is Err(AlreadyClaimed),
  )
  assert_eq(retire_preparation_capacity(prefix), Err(AlreadyTransferred))
  let duplicate : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(next, input)
  assert_true(duplicate is Err(AlreadyTransferred))
  // Growth/reconciliation cannot reset the one-time output choice.
  reserve_working_preparation_phase(next, input, 700L, 800L).unwrap()
  reconcile_working_preparation_phase(next, input, 500L, 600L).unwrap()
  let duplicate_after_resize : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(next, input)
  assert_true(duplicate_after_resize is Err(AlreadyTransferred))
  let body = ["compiled"]
  let compilation = begin_preparation_phase_work(next, input, ExecutionPlan, 20).unwrap()
  spend_preparation_phase_work(compilation, 4).unwrap()
  finish_preparation_phase_work(compilation).unwrap() |> ignore
  complete_preparation_capacity(next, input, body, 100L, 0L).unwrap()
  let holder = borrow_preparation_body(next).unwrap()
  assert_true(
    physical_equal(preparation_body_borrow_value(holder).unwrap(), body),
  )
  assert_true(borrow_preparation_body(next) is Err(InvalidExtent))
  assert_false(retire_preparation_capacity(next).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
  assert_eq(retire_preparation_capacity(prefix), Err(AlreadyTransferred))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 100L)
  assert_true(return_preparation_body_borrow(holder).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_eq(ledger_usage(ledger).planning_work, 0)
}

///|
test "preparation output continuation refuses foreign input, live work and an already completed body" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let foreign : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(prefix, [1])
  assert_true(foreign is Err(ForeignOriginal))
  let work = begin_preparation_phase_work(prefix, input, HeaderInspection, 10).unwrap()
  let active : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(prefix, input)
  assert_true(active is Err(WorkActive))
  finish_preparation_phase_work(work).unwrap() |> ignore
  complete_preparation_capacity(prefix, input, (), 100L, 0L).unwrap()
  let completed : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(prefix, input)
  assert_true(completed is Err(WorkActive))
  let holder = borrow_preparation_body(prefix).unwrap()
  let borrowed : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(prefix, input)
  assert_true(borrowed is Err(WorkActive))
  assert_false(retire_preparation_capacity(prefix).unwrap())
  assert_true(return_preparation_body_borrow(holder).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "preparation output continuation fences currentness reentry before consuming the old handle" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let armed = Ref(true)
  let observed = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        let nested : Result[
          PreparationCapacity[Array[Int], Bool],
          PreparationCapacityIssue,
        ] = continue_preparation_capacity(prefix, input)
        if nested is Err(WorkActive) {
          observed.val += 1
        }
        if retire_preparation_capacity(prefix) is Err(WorkActive) {
          observed.val += 1
        }
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
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let next : PreparationCapacity[Array[Int], Array[String]] = continue_preparation_capacity(
    prefix, input,
  ).unwrap()
  assert_eq(observed.val, 2)
  assert_true(prefix.input is None)
  assert_true(next.input is Some(original) && physical_equal(original, input))
  assert_true(abort_preparation_capacity_after_cleanup(next, input).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "preparation output continuation preserves the same pending debit when original currentness refuses" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => -41,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let refused : Result[
    PreparationCapacity[Array[Int], Array[String]],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(prefix, input)
  assert_true(refused is Err(Resource(ChildFundingUnavailable)))
  assert_true(prefix.phase == Working)
  assert_true(prefix.input is Some(original) && physical_equal(original, input))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 500L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 600L)
  assert_true(
    abort_preparation_capacity_after_cleanup(prefix, input)
    is Err(Resource(ChildFundingUnavailable)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 500L)
  // This numeric fixture intentionally retains unresolved debit; no stop,
  // physical backing or unknown-cleanup acknowledgement is fabricated.
}

///|
test "stopping refuses output selection without losing original cleanup" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => 1,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let refused : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(prefix, input)
  assert_true(refused is Err(Resource(ClosedReservation)))
  assert_true(prefix.phase == Working)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 500L)
  assert_true(abort_preparation_capacity_after_cleanup(prefix, input).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "output continuation invokes original current once before its callback-free post fence" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let calls = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    current_window: None,
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let next : PreparationCapacity[Array[Int], Bool] = continue_preparation_capacity(
    prefix, input,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 500L)
  // Cleanup is a later genuine transition with its own currentness duties.
  assert_true(abort_preparation_capacity_after_cleanup(next, input).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "public preparation continuation refuses census closure during its original current callback" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 2000L,
    execution_bytes: 2000L,
  }).unwrap()
  let bootstrap = reserve_capacity(ledger, 100L, 1L).unwrap()
  begin_original_ledger_inventory(ledger, bootstrap, 1, 0, 0).unwrap() |> ignore
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    500L,
    600L,
    max_borrowers=1,
  ).unwrap()
  let armed = Ref(true)
  let closed = Ref(false)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      if armed.val {
        armed.val = false
        closed.val = finish_original_ledger_inventory(ledger, false)
          is Ok(false)
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
    acquire_window: None,
    acquiring_window: false,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  let before = ledger_usage(ledger)
  let selected : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(owner, input)
  assert_true(closed.val)
  assert_true(selected is Err(Resource(ClosedReservation)))
  assert_true(owner.phase == Working && owner.input is Some(_))
  assert_eq(ledger_usage(ledger), before)
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
  assert_true(finish_original_ledger_inventory(ledger, true).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}
