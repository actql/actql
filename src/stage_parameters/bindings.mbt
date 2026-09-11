///|
pub(all) enum BindingsIssue {
  InvalidLimits
  WorkLimit
  ProgramBinding(@references.BindingIssue)
  StageBinding(Int, @references.BindingIssue)
} derive(Eq, Debug)

///|
struct BoundOperations {
  operations : CollectedOperations
  program : @references.BoundIndex
  stages : Array[@references.BoundIndex]
  usage : OperationsUsage
}

///|
/// Bind operation-only stage and Program-coordinate indexes to one complete
/// source-owned value set. The cap includes the retained collection work.
pub fn bind_operations(
  operations : CollectedOperations,
  values : @parameter.BoundValues,
  max_work~ : Int,
) -> Result[BoundOperations, BindingsIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let mut work = operations.usage.work
  if work > max_work {
    return Err(WorkLimit)
  }
  let program = match
    @references.bind_values(operations.index, values, max_work=max_work - work) {
    Ok(v) => v
    Err(e) => return Err(ProgramBinding(e))
  }
  work += @references.binding_work(program)
  let stages : Array[@references.BoundIndex] = []
  for i in 0..<operations.stages.length() {
    if work == max_work {
      return Err(WorkLimit)
    }
    work += 1
    let index = @collection.index(collection(operations.stages[i]))
    let stage = match
      @references.bind_values(index, values, max_work=max_work - work) {
      Ok(v) => v
      Err(e) => return Err(StageBinding(i, e))
    }
    work += @references.binding_work(stage)
    stages.push(stage)
  }
  Ok({ operations, program, stages, usage: { ..operations.usage, work, }, })
}

///|
pub fn bound_operations(v : BoundOperations) -> CollectedOperations {
  v.operations
}

///|
pub fn bound_program_index(v : BoundOperations) -> @references.BoundIndex {
  v.program
}

///|
pub fn bound_stage_at(
  v : BoundOperations,
  index : Int,
) -> @references.BoundIndex? {
  v.stages.get(index)
}

///|
pub fn bindings_usage(v : BoundOperations) -> OperationsUsage {
  v.usage
}
