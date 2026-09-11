///|
pub(all) enum EnvironmentIssue {
  InvalidLimits
  ForeignProgram
  ForeignInputs(Int)
  InconsistentUsage
  BudgetExceeded
} derive(Eq, Debug)

///|
struct EnvironmentContext {
  inputs : InputContexts
  snapshots : @local_inputs.ProgramEnvironmentInputs
  usage : InputUsage
}

///|
/// Bind complete supplied local snapshot coverage, not policy or Host admission.
pub fn attach_environment(
  inputs : InputContexts,
  snapshots : @local_inputs.ProgramEnvironmentInputs,
  max_work~ : Int,
  max_text_bytes~ : Int,
  max_local_input_nodes~ : Int,
) -> Result[EnvironmentContext, EnvironmentIssue] {
  if max_work < 0 || max_text_bytes < 0 || max_local_input_nodes < 0 {
    return Err(InvalidLimits)
  }
  let source = @stages.operations_source(
    @stages.bound_operations(inputs.wired.stages.operations),
  )
  if !physical_equal(@local_inputs.environment_program(snapshots), source) {
    return Err(ForeignProgram)
  }
  let cost = @local_inputs.program_environment_usage(snapshots)
  let mut added_work = cost.work
  let mut added_nodes = cost.nodes
  let mut added_text = cost.text_bytes
  let count = inputs.locals.length()
  if inputs.usage.work > max_work ||
    inputs.usage.text_bytes > max_text_bytes ||
    inputs.usage.local_input_nodes > max_local_input_nodes ||
    count > max_work - inputs.usage.work {
    return Err(BudgetExceeded)
  }
  for i in 0..<count {
    let stage = @local_inputs.program_environment_stage(snapshots, i).unwrap()
    let prepared = @local_inputs.snapshot_inputs(
      @local_inputs.environment_assertions(stage),
    )
    if !physical_equal(
        prepared,
        @local_inputs.attached_inputs(inputs.locals[i]),
      ) {
      return Err(ForeignInputs(i))
    }
    // Both branches charged this exact preparation once. No equal-shape or
    // equal-CID substitute can receive the shared-owner accounting discount.
    let prior = @local_inputs.usage(prepared)
    if prior.work > added_work ||
      prior.nodes > added_nodes ||
      prior.text_bytes > added_text {
      return Err(InconsistentUsage)
    }
    added_work -= prior.work
    added_nodes -= prior.nodes
    added_text -= prior.text_bytes
  }
  if added_work > max_work - inputs.usage.work - count ||
    added_nodes > max_local_input_nodes - inputs.usage.local_input_nodes ||
    added_text > max_text_bytes - inputs.usage.text_bytes {
    return Err(BudgetExceeded)
  }
  Ok({
    inputs,
    snapshots,
    usage: {
      work: inputs.usage.work + count + added_work,
      text_bytes: inputs.usage.text_bytes + added_text,
      local_input_nodes: inputs.usage.local_input_nodes + added_nodes,
    },
  })
}

///|
pub fn environment_inputs(v : EnvironmentContext) -> InputContexts {
  v.inputs
}

///|
pub fn environment_snapshots(
  v : EnvironmentContext,
) -> @local_inputs.ProgramEnvironmentInputs {
  v.snapshots
}

///|
pub fn environment_usage(v : EnvironmentContext) -> InputUsage {
  v.usage
}
