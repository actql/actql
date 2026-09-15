///|
pub enum SourceCapacityIssue {
  InvalidLimits
  BudgetExceeded
  Stage(Int, @sourceviews.LookupBoundsIssue)
}

///|
struct SourceCapacityContext {
  context : SourcePolicyContext
  contexts : StageContexts
  stages : Array[@sourceviews.LookupBounds]
  work : Int
}

///|
pub fn check_source_capacity(
  context : SourcePolicyContext,
  max_work : Int,
) -> Result[SourceCapacityContext, SourceCapacityIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let mut work = context.work
  if work > max_work {
    return Err(BudgetExceeded)
  }
  let stages = []
  for i in 0..<context.rows.stages.length() {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let result = match
      @sourceviews.check_lookup_bounds(
        context.rows.stages[i],
        context.policy.lookup,
        max_work - work,
      ) {
      Ok(v) => v
      Err(e) => return Err(Stage(i, e))
    }
    work += @sourceviews.lookup_bounds_work(result)
    stages.push(result)
  }
  Ok({ context, contexts: context.rows.requests.contexts, stages, work, })
}

///|
pub fn source_capacity_context(
  v : SourceCapacityContext,
) -> SourcePolicyContext {
  v.context
}

///|
pub fn source_capacity_work(v : SourceCapacityContext) -> Int {
  v.work
}

///|
pub fn source_capacity_stage(
  v : SourceCapacityContext,
  i : Int,
) -> @sourceviews.LookupBounds? {
  v.stages.get(i)
}
