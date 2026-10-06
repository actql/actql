///|
/// Additional checker declarations for pure operations. VecA and text-time
/// declarations are shared with the preparation's expression profile checks.
pub(all) struct PureOperationProfiles {
  rela : Bool
  sga : Bool
  tea : Bool
  calendar : Bool
  text_rank : Bool
} derive(Eq, Debug)

///|
pub(all) enum OperationProfilesIssue {
  InvalidLimits
  BudgetExceeded
  UnsupportedProfile(Int, Int, Int, @pipeline.OperationProfile)
} derive(Eq, Debug)

///|
struct OperationProfileChecks {
  preparation : ProgramPreparation
  declared : PureOperationProfiles
  graph : Bool
  count : Int
  work : Int
}

///|
/// Scan every owned stage and producer visit, not just the final current or
/// published Result. Indices in diagnostics are stage, visit and local step.
pub fn check_operation_profiles(
  preparation : ProgramPreparation,
  declared : PureOperationProfiles,
  max_work : Int,
  graph? : Bool = false,
) -> Result[OperationProfileChecks, OperationProfilesIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let mut work = preparation.usage.work
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let stages = preparation.selected.context.wired.stages
  let mut count = 0
  for stage in 0..<stages.contexts.length() {
    if work == max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let visits = stages.contexts[stage].visits
    for visit in 0..<visits.length() {
      if work == max_work {
        return Err(BudgetExceeded)
      }
      work += 1
      let pipeline = @parameter_slots.pipeline(visits[visit].collected)
      for step in 0..<@pipeline.step_count(pipeline) {
        let operation = @pipeline.step_at(pipeline, step).unwrap().operation
        let n = @pipeline.operation_profile_count(operation)
        if work >= max_work || n > max_work - work - 1 {
          return Err(BudgetExceeded)
        }
        work += n + 1
        for i in 0..<n {
          let profile = @pipeline.operation_profile_at(operation, i).unwrap()
          let claimed = match profile {
            RelA => declared.rela
            SGA => declared.sga
            // The new contract needs an explicit checker declaration; the
            // legacy SGA switch cannot silently claim its distinct laws.
            Graph => graph
            TEA => declared.tea
            VecA => preparation.profiles.profiles.veca
            CalendarProfile => declared.calendar
            TextRankProfile => declared.text_rank
          }
          if !claimed {
            return Err(UnsupportedProfile(stage, visit, step, profile))
          }
          count += 1
        }
      }
    }
  }
  Ok({ preparation, declared, graph, count, work, })
}

///|
/// A checker declaration only, not backend execution or resource admission.
pub fn operation_profiles_graph(v : OperationProfileChecks) -> Bool {
  v.graph
}

///|
pub fn operation_profiles_preparation(
  v : OperationProfileChecks,
) -> ProgramPreparation {
  v.preparation
}

///|
pub fn operation_profiles_declared(
  v : OperationProfileChecks,
) -> PureOperationProfiles {
  v.declared
}

///|
pub fn operation_profiles_count(v : OperationProfileChecks) -> Int {
  v.count
}

///|
pub fn operation_profiles_work(v : OperationProfileChecks) -> Int {
  v.work
}

///|
pub fn operation_profiles_diagnostic(v : OperationProfilesIssue) -> String? {
  match v {
    UnsupportedProfile(_, _, _, _) => Some("ACTQL_E_PROFILE_UNSUPPORTED")
    _ => None
  }
}
