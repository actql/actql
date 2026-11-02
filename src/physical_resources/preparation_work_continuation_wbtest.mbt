///|
fn original_continuous_work_capacity() -> (
  Ledger,
  Array[Int],
  PreparationCapacity[Array[Int], Unit],
) {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let capacity = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    20L,
    max_borrowers=1,
  ).unwrap()
  (ledger, input, capacity)
}

///|
test "one original work receipt survives returned constructors without refilling phase credit" {
  let (ledger, input, owner) = original_continuous_work_capacity()
  let work = begin_preparation_phase_work_continuation64(
    owner,
    input,
    SemanticCheck,
    7L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(work, 2L).unwrap()
  assert_true(
    reserve_working_preparation_phase(owner, input, 60L, 30L) is Err(WorkActive),
  )
  return_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(
    spend_preparation_phase_work_continuation64(work, 1L),
    Err(WrongPhase),
  )
  assert_eq(return_preparation_phase_work_continuation64(work), Err(WrongPhase))
  assert_eq(preparation_capacity_working_extents(owner, input), Ok((40L, 20L)))
  reserve_working_preparation_phase(owner, input, 60L, 30L).unwrap()
  resume_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(resume_preparation_phase_work_continuation64(work), Err(WrongPhase))
  spend_preparation_phase_work_continuation64(work, 3L).unwrap()
  return_preparation_phase_work_continuation64(work).unwrap()
  reconcile_working_preparation_phase(owner, input, 50L, 25L).unwrap()
  reserve_working_preparation_phase(owner, input, 70L, 40L).unwrap()
  resume_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(
    spend_preparation_phase_work_continuation64(work, 3L),
    Err(WorkLimit),
  )
  spend_preparation_phase_work_continuation64(work, 2L).unwrap()
  assert_eq(finish_preparation_phase_work_continuation64(work), Ok(7L))
  assert_eq(resume_preparation_phase_work_continuation64(work), Err(Closed))
  assert_eq(return_preparation_phase_work_continuation64(work), Err(Closed))
  assert_true(
    begin_preparation_phase_work_continuation64(owner, input, SemanticCheck, 7L)
    is Err(AlreadyClaimed),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 70L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 40L)
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "declined growth keeps original returned work and blocks completion transfer and reissue" {
  let (ledger, input, owner) = original_continuous_work_capacity()
  let work = begin_preparation_phase_work_continuation64(
    owner,
    input,
    SemanticCheck,
    7L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(work, 3L).unwrap()
  return_preparation_phase_work_continuation64(work).unwrap()
  let other = reserve_capacity(ledger, 30L, 10L).unwrap()
  assert_true(
    reserve_working_preparation_phase(owner, input, 71L, 40L)
    is Err(Resource(RetentionLimit)),
  )
  assert_eq(preparation_capacity_working_extents(owner, input), Ok((40L, 20L)))
  assert_true(
    reserve_working_preparation_phase(owner, [1], 60L, 30L)
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_preparation_phase_work64(owner, input, LowerAndGraph, 7L)
    is Err(WrongPhase),
  )
  assert_true(
    complete_preparation_capacity(owner, input, (), 40L, 20L) is Err(WorkActive),
  )
  let next : Result[
    PreparationCapacity[Array[Int], Bool],
    PreparationCapacityIssue,
  ] = continue_preparation_capacity(owner, input)
  assert_true(next is Err(WorkActive))
  assert_true(
    abort_preparation_capacity_after_cleanup(owner, input) is Err(WorkActive),
  )
  settle_capacity(ledger, other).unwrap()
  reserve_working_preparation_phase(owner, input, 71L, 40L).unwrap()
  resume_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(
    spend_preparation_phase_work_continuation64(work, 5L),
    Err(WorkLimit),
  )
  spend_preparation_phase_work_continuation64(work, 4L).unwrap()
  assert_eq(finish_preparation_phase_work_continuation64(work), Ok(7L))
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
}

///|
test "returned work fences resize callback reentry without another current observation" {
  let (ledger, input, owner) = original_continuous_work_capacity()
  let work = begin_preparation_phase_work_continuation64(
    owner,
    input,
    SemanticCheck,
    7L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(work, 3L).unwrap()
  return_preparation_phase_work_continuation64(work).unwrap()
  let calls = Ref(0)
  let fenced = Ref(0)
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => {
      calls.val += 1
      if resume_preparation_phase_work_continuation64(work) is Err(WrongPhase) {
        fenced.val += 1
      }
      if finish_preparation_phase_work_continuation64(work) is Err(WrongPhase) {
        fenced.val += 1
      }
      if abort_preparation_capacity_after_cleanup(owner, input)
        is Err(AlreadyCompleted) {
        fenced.val += 1
      }
      0
    },
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    ledger: Some(ledger),
    stopping: false,
    unavailable: false,
  })
  assert_eq(preparation_capacity_working_extents(owner, input), Ok((40L, 20L)))
  assert_eq(calls.val, 0)
  reserve_working_preparation_phase(owner, input, 60L, 30L).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(fenced.val, 3)
  resume_preparation_phase_work_continuation64(work).unwrap()
  spend_preparation_phase_work_continuation64(work, 1L).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(finish_preparation_phase_work_continuation64(work), Ok(4L))
  ledger.imported_child = None
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
}

///|
test "stopping returned work preserves its original debit and cleanup history" {
  let (ledger, input, owner) = original_continuous_work_capacity()
  let work = begin_preparation_phase_work_continuation64(
    owner,
    input,
    SemanticCheck,
    7L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(work, 2L).unwrap()
  return_preparation_phase_work_continuation64(work).unwrap()
  ledger.imported_child = Some({
    nonce: 1L,
    admit: _ => 0,
    current: _ => 0,
    limit: (_, _) => 0L,
    capacity: (_, _) => 0L,
    report: (_, _) => 0,
    stop: _ => 0,
    fixed_capacities: false,
    working: None,
    ledger: Some(ledger),
    stopping: true,
    unavailable: false,
  })
  assert_eq(resume_preparation_phase_work_continuation64(work), Err(Stopping))
  assert_true(
    reserve_working_preparation_phase(owner, input, 60L, 30L)
    is Err(Resource(ClosedReservation)),
  )
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_eq(ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_eq(finish_preparation_phase_work_continuation64(work), Ok(2L))
  ledger.imported_child = None
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
}

///|
test "ordinary narrow staged and ordinary wide receipts keep one original phase history" {
  let (_, input, owner) = original_continuous_work_capacity()
  let first = begin_preparation_phase_work(owner, input, ProgramStructure, 5).unwrap()
  spend_preparation_phase_work(first, 2).unwrap()
  assert_eq(finish_preparation_phase_work(first), Ok(2))
  let staged = begin_preparation_phase_work_continuation64(
    owner,
    input,
    SemanticCheck,
    7L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(staged, 3L).unwrap()
  return_preparation_phase_work_continuation64(staged).unwrap()
  assert_true(
    begin_preparation_phase_work(owner, input, LowerAndGraph, 5)
    is Err(WrongPhase),
  )
  reserve_working_preparation_phase(owner, input, 60L, 30L).unwrap()
  resume_preparation_phase_work_continuation64(staged).unwrap()
  spend_preparation_phase_work_continuation64(staged, 1L).unwrap()
  assert_eq(finish_preparation_phase_work_continuation64(staged), Ok(4L))
  assert_true(
    begin_preparation_phase_work64(owner, input, SemanticCheck, 20L)
    is Err(AlreadyClaimed),
  )
  let last = begin_preparation_phase_work64(owner, input, LowerAndGraph, 9L).unwrap()
  spend_preparation_phase_work64(last, 3L).unwrap()
  assert_eq(finish_preparation_phase_work64(last), Ok(3L))
  assert_true(abort_preparation_capacity_after_cleanup(owner, input).unwrap())
}
