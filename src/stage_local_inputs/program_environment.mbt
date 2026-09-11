///|
pub enum ProgramEnvironmentIssue {
  InvalidLimits
  BudgetExceeded
  StageCountMismatch
  ForeignProgram(Int)
  ForeignEnvironment(Int)
  DuplicateStage(Int)
  DuplicateMember(Int)
  UncheckedSnapshot(Int)
}

///|
struct ProgramEnvironmentInputs {
  source : @stages.Source
  environment : @environment.WireEnvironment
  stages : Array[EnvironmentInputs]
  usage : Usage
}

///|
/// Collect every stage and every supplied snapshot, not all environment semantics.
/// This local-Relation path cannot silently omit unsupported snapshot kinds.
pub fn assemble_environment(
  source : @stages.Source,
  environment : @environment.WireEnvironment,
  stages : Array[EnvironmentInputs],
  limits : Limits,
) -> Result[ProgramEnvironmentInputs, ProgramEnvironmentIssue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  let count = @stages.stage_count(source)
  if stages.length() != count {
    return Err(StageCountMismatch)
  }
  let members = @environment.member_count(
    environment,
    @environment.SchemaSnapshots,
  )
  let mut work = limits.max_work
  let mut nodes = limits.max_nodes
  let mut text = limits.max_text_bytes
  for cost in [count, members] {
    if cost > work {
      return Err(BudgetExceeded)
    }
    work -= cost
  }
  // Preflight prior pass costs before allocating indexes. No CID-based sharing
  // discount: separate stage passes retain their own previously recorded work.
  for stage in stages {
    let cost = environment_usage(stage)
    if cost.work > work || cost.nodes > nodes || cost.text_bytes > text {
      return Err(BudgetExceeded)
    }
    work -= cost.work
    nodes -= cost.nodes
    text -= cost.text_bytes
  }
  let positions : Array[EnvironmentInputs?] = Array::make(count, None)
  let covered = Array::make(members, false)
  for i in 0..<stages.length() {
    let value = stages[i]
    let prepared = snapshot_inputs(environment_assertions(value))
    if !physical_equal(prepared.source, source) {
      return Err(ForeignProgram(i))
    }
    if !physical_equal(input_environment(value), environment) {
      return Err(ForeignEnvironment(i))
    }
    if positions[prepared.stage] is Some(_) {
      return Err(DuplicateStage(prepared.stage))
    }
    positions[prepared.stage] = Some(value)
    for j in 0..<snapshot_count(environment_assertions(value)) {
      if work == 0 {
        return Err(BudgetExceeded)
      }
      work -= 1
      let entry = @snapshot.environment_member(
        environment_snapshot_at(value, j).unwrap(),
      )
      let at = @environment.member_index(entry)
      if covered[at] {
        return Err(DuplicateMember(at))
      }
      covered[at] = true
    }
  }
  for i in 0..<members {
    if !covered[i] {
      return Err(UncheckedSnapshot(i))
    }
  }
  Ok({
    source,
    environment,
    stages: positions.map(v => v.unwrap()),
    usage: {
      work: limits.max_work - work,
      nodes: limits.max_nodes - nodes,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn environment_program(v : ProgramEnvironmentInputs) -> @stages.Source {
  v.source
}

///|
pub fn program_environment(
  v : ProgramEnvironmentInputs,
) -> @environment.WireEnvironment {
  v.environment
}

///|
pub fn program_environment_stage(
  v : ProgramEnvironmentInputs,
  i : Int,
) -> EnvironmentInputs? {
  v.stages.get(i)
}

///|
pub fn program_environment_usage(v : ProgramEnvironmentInputs) -> Usage {
  v.usage
}
