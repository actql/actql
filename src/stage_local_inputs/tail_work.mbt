///|
/// SAME Local remainder before the first original declaration/assembly. The
/// original reader's semantic pass convention bounds its whole remaining tail;
/// nested parser/UTF work is not invented from this scalar policy amount.
pub fn local_environment_tail_work_bound(
  read : LocalEnvironmentPreparation,
) -> Int? {
  match read.state {
    ReadDeclaration(0) | AssembleStages => Some(read.work)
    _ => None
  }
}

///|
/// One original remaining constructor. A successful declaration reports its
/// own prepared Usage; reconciliation excludes that already reported prefix;
/// final assembly excludes all original prior Local passes. A failed nested
/// call without returned Usage remains None, never a fabricated zero or total.
/// The outer parent retains completed debits and the failed peak until clear.
pub fn observe_advance_local_environment_tail(
  read : LocalEnvironmentPreparation,
) -> (LocalEnvironmentPhase, Int?) {
  match read.state {
    ReadDeclaration(_) => {
      let phase = advance_local_environment_preparation(read)
      let spent = match read.state {
        ReconcileStage(_) => Some(usage(read.pending.unwrap().prepared).work)
        _ => None
      }
      (phase, spent)
    }
    ReconcileStage(_) => {
      let prefix = usage(read.pending.unwrap().prepared).work
      let before = read.work
      let phase = advance_local_environment_preparation(read)
      let spent = if phase == LocalEnvironmentFailed {
        None
      } else {
        Some(before - read.work - prefix)
      }
      (phase, spent)
    }
    AssembleStages => {
      let prior = read.arguments.unwrap().limits.max_work - read.work
      let phase = advance_local_environment_preparation(read)
      let spent = match read.state {
        LocalDone(Ok(result)) =>
          Some(program_environment_usage(result).work - prior)
        _ => None
      }
      (phase, spent)
    }
    _ => (local_environment_preparation_phase(read), None)
  }
}

///|
pub fn local_environment_tail_work_observation_extent() -> @shape.CollectionConstructionExtent {
  local_budget_observation_units
}
