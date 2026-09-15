///|
pub enum SourceBindingsIssue {
  InvalidLimits
  BudgetExceeded
  Request(Int, Int, @sourceviews.RequestBindingsIssue)
}

///|
struct SourceBindingRequirements {
  preparation : ProgramPreparation
  stages : Array[Array[@sourceviews.RequestBindings]]
  count : Int
  work : Int
}

///|
/// Inventory unresolved Host Binding uses in every classified source request.
/// Absence of uses is not Reference admission, source authority or Plan readiness.
pub fn collect_source_bindings(
  preparation : ProgramPreparation,
  max_work : Int,
  max_bindings : Int,
) -> Result[SourceBindingRequirements, SourceBindingsIssue] {
  if max_work < 0 || max_bindings < 0 {
    return Err(InvalidLimits)
  }
  let mut work = preparation.usage.work
  if work >= max_work {
    return Err(BudgetExceeded)
  }
  work += 1
  let requests = preparation.requests
  let stages = []
  let mut count = 0
  for i in 0..<requests.stages.length() {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let stage = requests.stages[i]
    let entries = []
    for j in 0..<@sourceviews.pipeline_requests_count(stage) {
      let result = match @sourceviews.pipeline_request_at(stage, j).unwrap() {
        Direct(_, request) =>
          @sourceviews.direct_request_bindings(
            request,
            max_work - work,
            max_bindings - count,
          )
        Keyed(_, request) =>
          @sourceviews.keyed_request_bindings(
            request,
            max_work - work,
            max_bindings - count,
          )
      }
      let bindings = match result {
        Ok(v) => v
        Err(e) => return Err(Request(i, j, e))
      }
      work += @sourceviews.request_bindings_work(bindings)
      count += @sourceviews.request_bindings_count(bindings)
      entries.push(bindings)
    }
    stages.push(entries)
  }
  Ok({ preparation, stages, count, work, })
}

///|
pub fn source_bindings_preparation(
  v : SourceBindingRequirements,
) -> ProgramPreparation {
  v.preparation
}

///|
pub fn source_bindings_count(v : SourceBindingRequirements) -> Int {
  v.count
}

///|
pub fn source_bindings_work(v : SourceBindingRequirements) -> Int {
  v.work
}

///|
pub fn source_bindings_at(
  v : SourceBindingRequirements,
  stage : Int,
  input : Int,
) -> @sourceviews.RequestBindings? {
  v.stages.get(stage).bind(entries => entries.get(input))
}
