///|
pub enum SourceRowsIssue {
  InvalidLimits
  StageCountMismatch
  BudgetExceeded
  Stage(Int, @sourceviews.KeyedRowsIssue)
  InvalidVisit(Int, Int)
  InvalidClaim(Int, Int)
  MissingPositiveBound(Int, Int)
  Target(Int, Int, @step_bounds.TargetRowsIssue)
}

///|
struct SourceRowContexts {
  requests : SourceRequestContexts
  stages : Array[@sourceviews.KeyedRowBounds]
  work : Int
}

///|
/// Coordinates select already owned capacity applications, never independent
/// successful TargetRows. Request classification determines each left target.
fn prepare_source_row_bounds(
  requests : SourceRequestContexts,
  locations : Array[Array[(Int, Int)]],
  max_work : Int,
) -> Result[SourceRowContexts, SourceRowsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if locations.length() != requests.keyed_facts.length() {
    return Err(StageCountMismatch)
  }
  let mut work = requests.work
  if work > max_work {
    return Err(BudgetExceeded)
  }
  let stages = []
  let operations = @stages.bound_operations(requests.contexts.operations)
  for stage in 0..<locations.length() {
    if work >= max_work {
      return Err(BudgetExceeded)
    }
    work += 1
    let facts = requests.keyed_facts[stage]
    let joins = @sourceviews.keyed_facts_joins(facts)
    let count = @sourceviews.keyed_facts_count(facts)
    if locations[stage].length() != count {
      return Err(Stage(stage, @sourceviews.CountMismatch))
    }
    let pipeline = @parameter_slots.pipeline(
      @stages.collection(
        @stages.operations_stage_at(operations, stage).unwrap(),
      ),
    )
    let closure = requests.contexts.contexts[stage].context.capacity
    let bounds = []
    let mut traversal = 0
    for index in 0..<count {
      // Reserve the existing row checker visit before constructing a target.
      // It will charge traversal once; orchestration visits remain additional.
      if max_work - work < 2 || traversal > max_work - work - 2 {
        return Err(BudgetExceeded)
      }
      work += 1
      traversal += 1
      let (visit, claim) = locations[stage][index]
      guard @capacity.application_closure_at(closure, visit) is Some(coverage) else {
        return Err(InvalidVisit(stage, index))
      }
      let applications = @capacity.source_coverage_program(
        @capacity.application_coverage_sources(coverage),
      )
      guard @step_bounds.application_at(applications, claim) is Some(bound) else {
        return Err(InvalidClaim(stage, index))
      }
      let target = @sourceviews.keyed_join_left(
        @sourceviews.keyed_join_at(joins, index).unwrap(),
      )
      let rows = match
        @step_bounds.check_target_rows(
          pipeline,
          target,
          bound,
          max_work - work - traversal,
        ) {
        Ok(v) => v
        Err(e) => return Err(Target(stage, index, e))
      }
      traversal += @step_bounds.target_rows_work(rows)
      bounds.push(rows)
    }
    let checked = match
      @sourceviews.check_keyed_row_bounds(facts, bounds, max_work - work) {
      Ok(v) => v
      Err(e) => return Err(Stage(stage, e))
    }
    work += @sourceviews.keyed_rows_work(checked)
    stages.push(checked)
  }
  Ok({ requests, stages, work, })
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
