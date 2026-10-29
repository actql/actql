///|
test "wide preparation work retains original phase ownership beyond Int without changing narrow callers" {
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
  let old = begin_preparation_phase_work(owner, input, LexicalScan, 5).unwrap()
  spend_preparation_phase_work(old, 2).unwrap()
  assert_eq(finish_preparation_phase_work(old), Ok(2))
  assert_true(
    begin_preparation_phase_work64(owner, input, LexicalScan, 500L)
    is Err(AlreadyClaimed),
  )
  assert_true(
    begin_preparation_phase_work64(owner, [1], SourceAndIndex, 5L)
    is Err(ForeignOriginal),
  )
  let wide = begin_preparation_phase_work64(
    owner,
    input,
    SourceAndIndex,
    2147483650L,
  ).unwrap()
  assert_true(
    begin_preparation_phase_work(owner, input, SemanticCheck, 1)
    is Err(WrongPhase),
  )
  assert_eq(spend_preparation_phase_work64(wide, -1L), Err(InvalidWork))
  spend_preparation_phase_work64(wide, 2147483649L).unwrap()
  assert_eq(spend_preparation_phase_work64(wide, 2L), Err(WorkLimit))
  spend_preparation_phase_work64(wide, 1L).unwrap()
  assert_eq(finish_preparation_phase_work64(wide), Ok(2147483650L))
  assert_eq(finish_preparation_phase_work64(wide), Err(Closed))
  assert_eq(spend_preparation_phase_work64(wide, 0L), Err(Closed))
  assert_eq(ledger_usage(ledger).planning_work, 0)
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  abort_preparation_capacity_after_cleanup(owner, input).unwrap() |> ignore
}

///|
test "wide preparation work preserves selected original parent phase and cleanup finish" {
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
  // Existing selected-parent phase remains valid. This is an internal state
  // fixture; it issues no Host/physical currentness or retirement witness.
  owner.phase = SelectedWorking
  let work = begin_preparation_phase_work64(owner, input, ProgramStructure, 7L).unwrap()
  spend_preparation_phase_work64(work, 3L).unwrap()
  owner.phase = Retiring
  assert_eq(spend_preparation_phase_work64(work, 1L), Err(WrongPhase))
  // As before, finishing actual returned work is allowed during cleanup.
  assert_eq(finish_preparation_phase_work64(work), Ok(3L))
  owner.phase = SelectedWorking
  let next = begin_preparation_phase_work64(owner, input, SemanticCheck, 2L).unwrap()
  spend_preparation_phase_work64(next, 2L).unwrap()
  assert_eq(finish_preparation_phase_work64(next), Ok(2L))
  let semantic = begin_preparation_phase_work(owner, input, LowerAndGraph, 1).unwrap()
  assert_eq(finish_preparation_phase_work(semantic), Ok(0))
  abort_preparation_capacity_after_cleanup(owner, input).unwrap() |> ignore
}
