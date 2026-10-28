///|
/// SAME Local max_work remainder before the first/next original member.
/// This bounds Local member/node/name charges, not all nested parser work.
pub fn local_environment_snapshots_work_bound(
  read : LocalEnvironmentPreparation,
) -> Int? {
  guard read.state is ReadSnapshot(_) else { return None }
  Some(read.work)
}

///|
/// Advance exactly one original Snapshot step, retaining its actual Local
/// budget debit even on failure. None means this step was not entered.
/// Some(0) is a real zero Local debit, not zero emission/parse/schema work.
/// The caller must back the complete body before entering; no Resource owner,
/// capacity claim, permission or physical retirement is issued here.
pub fn observe_advance_local_environment_snapshot(
  read : LocalEnvironmentPreparation,
) -> (LocalEnvironmentPhase, Int?) {
  guard read.state is ReadSnapshot(_) else {
    return (local_environment_preparation_phase(read), None)
  }
  let before = read.work
  let phase = advance_local_environment_preparation(read)
  (phase, Some(before - read.work))
}

///|
// Additional original phase/debit pair1H1R1W and Local debit Some1H2W.

///|
/// The Source holder retains that SAME Some; no second observation is created.
let local_budget_observation_units : @shape.CollectionConstructionExtent = {
  record_headers: 2L,
  reference_slots: 1L,
  scalar_words: 3L,
}

///|
pub fn local_environment_snapshot_work_observation_extent() -> @shape.CollectionConstructionExtent {
  local_budget_observation_units
}
