///|
pub(all) enum InputIssue {
  InvalidLimits
  StageCount
  ForeignStage(Int)
  InconsistentUsage
  BudgetExceeded(Int)
} derive(Eq, Debug)

///|
pub(all) struct InputUsage {
  work : Int
  text_bytes : Int
  local_input_nodes : Int
} derive(Eq, Debug)

///|
struct InputContexts {
  wired : WiredStages
  locals : Array[@local_inputs.Attached]
  usage : InputUsage
}

///|
/// Attach all source-only local input results. Receipt/Host admission, duplicate
/// order resolution, static discharge and semantic identity remain separate.
pub fn attach_local_inputs(
  wired : WiredStages,
  locals : Array[@local_inputs.Attached],
  max_work~ : Int,
  max_text_bytes~ : Int,
  max_local_input_nodes~ : Int,
) -> Result[InputContexts, InputIssue] {
  if max_work < 0 || max_text_bytes < 0 || max_local_input_nodes < 0 {
    return Err(InvalidLimits)
  }
  let operations = @stages.bound_operations(wired.stages.operations)
  let count = wired.stages.contexts.length()
  if locals.length() != count {
    return Err(StageCount)
  }
  let mut work = wired.work
  let mut text = wired.text
  let mut nodes = 0
  if work > max_work || text > max_text_bytes {
    return Err(BudgetExceeded(0))
  }
  let retained = []
  for i in 0..<count {
    let attached = locals[i]
    let expected = @stages.operations_stage_at(operations, i).unwrap()
    if !physical_equal(@local_inputs.attached_stage(attached), expected) {
      return Err(ForeignStage(i))
    }
    let prior = @stages.collection_work(expected)
    let local_work = @local_inputs.attached_work(attached)
    if prior > local_work {
      return Err(InconsistentUsage)
    }
    // Exact shared operation collection is already counted by WiredStages.
    let added = local_work - prior
    let usage = @local_inputs.usage(@local_inputs.attached_inputs(attached))
    if work == max_work ||
      added > max_work - work - 1 ||
      usage.text_bytes > max_text_bytes - text ||
      usage.nodes > max_local_input_nodes - nodes {
      return Err(BudgetExceeded(i))
    }
    work += 1 + added
    text += usage.text_bytes
    nodes += usage.nodes
    retained.push(attached)
  }
  Ok({
    wired,
    locals: retained,
    usage: { work, text_bytes: text, local_input_nodes: nodes, },
  })
}

///|
pub fn input_wiring(value : InputContexts) -> WiredStages {
  value.wired
}

///|
pub fn local_inputs_at(
  value : InputContexts,
  index : Int,
) -> @local_inputs.Attached? {
  value.locals.get(index)
}

///|
pub fn input_usage(value : InputContexts) -> InputUsage {
  value.usage
}
