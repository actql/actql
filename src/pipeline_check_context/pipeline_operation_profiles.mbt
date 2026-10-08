///|
pub(all) enum PipelineOperationProfilesIssue {
  InvalidLimits
  BudgetExceeded
  UnsupportedProfile(Int, @pipeline.OperationProfile)
} derive(Eq, Debug)

///|
struct PipelineOperationProfileChecks {
  pipeline : @pipeline.CheckedPipeline
  declared : PureOperationProfiles
  expressions : ExpressionProfiles
  graph : Bool
  count : Int
  work : Int
}

///|
/// Admit every declared operation profile in one exact checked pipeline without
/// requiring effective Parameter values. This is a profile-declaration witness,
/// not expression/operation obligation closure, resource or execution admission.
/// Work measures this traversal; the enclosing owner retains its prior pipeline
/// preparation prefix rather than accepting a caller-supplied accounting credit.
pub fn check_pipeline_operation_profiles(
  pipeline : @pipeline.CheckedPipeline,
  declared : PureOperationProfiles,
  expressions : ExpressionProfiles,
  max_work : Int,
  graph? : Bool = false,
) -> Result[PipelineOperationProfileChecks, PipelineOperationProfilesIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if max_work == 0 {
    return Err(BudgetExceeded)
  }
  let mut work = 1
  let mut count = 0
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
        GraphProfile => graph
        TEA => declared.tea
        VecA => expressions.veca
        CalendarProfile => declared.calendar
        TextRankProfile => declared.text_rank
      }
      if !claimed {
        return Err(UnsupportedProfile(step, profile))
      }
      count += 1
    }
  }
  Ok({ pipeline, declared, expressions, graph, count, work, })
}

///|
pub fn pipeline_operation_profiles_pipeline(
  value : PipelineOperationProfileChecks,
) -> @pipeline.CheckedPipeline {
  value.pipeline
}

///|
pub fn pipeline_operation_profiles_count(
  value : PipelineOperationProfileChecks,
) -> Int {
  value.count
}

///|
pub fn pipeline_operation_profiles_work(
  value : PipelineOperationProfileChecks,
) -> Int {
  value.work
}

///|
pub fn pipeline_operation_profiles_declared(
  value : PipelineOperationProfileChecks,
) -> PureOperationProfiles {
  value.declared
}

///|
pub fn pipeline_operation_profiles_expressions(
  value : PipelineOperationProfileChecks,
) -> ExpressionProfiles {
  value.expressions
}

///|
pub fn pipeline_operation_profiles_graph(
  value : PipelineOperationProfileChecks,
) -> Bool {
  value.graph
}
