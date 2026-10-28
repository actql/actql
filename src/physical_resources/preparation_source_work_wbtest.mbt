///|
test "Source collection phases preserve consumed history through the original typed capacity continuation" {
  let ledger = create_ledger({
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 100L,
    execution_bytes: 100L,
  }).unwrap()
  let input = [1]
  let prefix : PreparationCapacity[Array[Int], Unit] = reserve_preparation_capacity(
    ledger,
    input,
    40L,
    50L,
    max_borrowers=1,
  ).unwrap()
  for
    phase in [
      CatalogRequestsAdmission,
      SourceCollectionInspection,
      SourceCollection,
      SourceResolutionInspection,
      SourceSelection,
      SourcePipelineRegistration,
      SourceLocalEntry,
      SourceLocalIndexInspection,
      SourceLocalIndex,
      SourceLocalGroups,
      SourceLocalSnapshotReferenceInspection,
    ] {
    let work = begin_preparation_phase_work64(prefix, input, phase, 7L).unwrap()
    spend_preparation_phase_work64(work, 3L).unwrap()
    assert_true(
      begin_preparation_phase_work64(prefix, input, SemanticCheck, 1L)
      is Err(WrongPhase),
    )
    assert_eq(finish_preparation_phase_work64(work), Ok(3L))
    assert_true(
      begin_preparation_phase_work64(prefix, input, phase, 7L)
      is Err(AlreadyClaimed),
    )
  }
  let next : PreparationCapacity[Array[Int], Array[Int]] = continue_preparation_capacity(
    prefix, input,
  ).unwrap()
  assert_true(physical_equal(prefix.reservation, next.reservation))
  reserve_working_preparation_phase(next, input, 60L, 70L).unwrap()
  reconcile_working_preparation_phase(next, input, 40L, 50L).unwrap()
  for
    phase in [
      CatalogRequestsAdmission,
      SourceCollectionInspection,
      SourceCollection,
      SourceResolutionInspection,
      SourceSelection,
      SourcePipelineRegistration,
      SourceLocalEntry,
      SourceLocalIndexInspection,
      SourceLocalIndex,
      SourceLocalGroups,
      SourceLocalSnapshotReferenceInspection,
    ] {
    assert_true(
      begin_preparation_phase_work64(next, input, phase, 7L)
      is Err(AlreadyClaimed),
    )
  }
  let check = begin_preparation_phase_work64(next, input, SemanticCheck, 5L).unwrap()
  spend_preparation_phase_work64(check, 4L).unwrap()
  assert_eq(finish_preparation_phase_work64(check), Ok(4L))
  assert_true(retire_preparation_capacity(prefix) is Err(AlreadyTransferred))
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 40L)
  assert_eq(ledger_usage(ledger).attempts, 0)
  assert_true(abort_preparation_capacity_after_cleanup(next, input).unwrap())
  assert_eq(ledger_usage(ledger).reserved_retention_bytes, 0L)
}
