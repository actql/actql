///|
pub enum SourceRowsIssue {
  InvalidLimits
  StageCountMismatch
  BudgetExceeded
  Stage(Int, @sourceviews.KeyedRowsIssue)
}

///|
struct SourceRowContexts {
  requests : SourceRequestContexts
  stages : Array[@sourceviews.KeyedRowBounds]
  work : Int
}

///|
/// Close left-target row bindings for every classified stage, retaining the
/// exact request owner. This does not close Host execution or producer obligations.
pub fn check_source_row_bounds(
  requests : SourceRequestContexts,
  bounds : Array[Array[@step_bounds.TargetRows]],
  max_work : Int,
) -> Result[SourceRowContexts, SourceRowsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if bounds.length() != requests.keyed_facts.length() {
    return Err(StageCountMismatch)
  }
  let mut work = requests.work
  if work > max_work {
    return Err(BudgetExceeded)
  }
  let stages = []
  for i in 0..<bounds.length() {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let stage = match
      @sourceviews.check_keyed_row_bounds(
        requests.keyed_facts[i],
        bounds[i],
        max_work - work,
      ) {
      Ok(v) => v
      Err(e) => return Err(Stage(i, e))
    }
    work += @sourceviews.keyed_rows_work(stage)
    stages.push(stage)
  }
  Ok({ requests, stages, work, })
}

///|
pub fn source_rows_requests(v : SourceRowContexts) -> SourceRequestContexts {
  v.requests
}

///|
pub fn source_rows_work(v : SourceRowContexts) -> Int {
  v.work
}

///|
pub fn source_rows_stage(
  v : SourceRowContexts,
  i : Int,
) -> @sourceviews.KeyedRowBounds? {
  v.stages.get(i)
}
