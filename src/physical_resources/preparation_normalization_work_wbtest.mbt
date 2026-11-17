///|
test "normalization work is once between original lowering and Plan and keeps returned current and cleanup fences" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let owner : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    40L,
    max_borrowers=1,
  ).unwrap()
  let lower = begin_preparation_phase_work64(owner, input, LowerAndGraph, 10L).unwrap()
  spend_preparation_phase_work64(lower, 2L).unwrap()
  assert_eq(finish_preparation_phase_work64(lower), Ok(2L))
  assert_true(
    begin_preparation_phase_work64(owner, [1], NormalizationAudit, 10L)
    is Err(ForeignOriginal),
  )
  let work = begin_preparation_phase_work_continuation64(
    owner,
    input,
    NormalizationAudit,
    10L,
  ).unwrap()
  spend_preparation_phase_work_continuation64(work, 3L).unwrap()
  assert_true(
    reserve_working_preparation_phase(owner, input, 50L, 50L) is Err(WorkActive),
  )
  return_preparation_phase_work_continuation64(work).unwrap()
  reserve_working_preparation_phase(owner, input, 50L, 50L).unwrap()
  assert_true(
    begin_preparation_phase_work64(owner, input, ExecutionPlan, 10L)
    is Err(WrongPhase),
  )
  resume_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(finish_preparation_phase_work_continuation64(work), Ok(3L))
  assert_true(
    begin_preparation_phase_work64(owner, input, NormalizationAudit, 10L)
    is Err(AlreadyClaimed),
  )
  assert_true(
    begin_preparation_phase_work64(owner, input, LowerAndGraph, 10L)
    is Err(AlreadyClaimed),
  )
  let plan = begin_preparation_phase_work64(owner, input, ExecutionPlan, 10L).unwrap()
  assert_eq(finish_preparation_phase_work64(plan), Ok(0L))
  assert_true(
    begin_preparation_phase_work64(owner, input, NormalizationAudit, 10L)
    is Err(AlreadyClaimed),
  )
  let proof = begin_preparation_phase_work64(
    owner,
    input,
    PublicationProof,
    10L,
  ).unwrap()
  assert_eq(finish_preparation_phase_work64(proof), Ok(0L))
  assert_eq(ledger_usage(ledger).planning_work, 0)
  abort_preparation_capacity_after_cleanup(owner, input).unwrap() |> ignore
}
