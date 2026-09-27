///|
/// An owned reference to an already checked task, not a completion or a permit.
/// Retains semantic preparation only, never a running DAG, buffers or holdings.
struct CheckedTaskReference {
  graph : CheckedDAG
  task : Int
  target : @pipeline.Target
  identity : CheckedTaskIdentity
}

///|
/// Bounded local-transport projection of existing canonical identities. These
/// fields do not define a new canonical preimage or prove an execution occurred.
pub(all) struct CheckedTaskIdentity {
  task : Int
  program_definition_cid : String
  program_parameters_cid : String
  unit_definition_cid : String
  unit_parameters_cid : String
  unit_contracts_cid : String
  output_step : Int
  inputs : Array[CheckedTaskInputIdentity]
  controls : Array[Int]
} derive(Eq, Debug)

///|
pub(all) struct CheckedTaskInputIdentity {
  input : Int
  producer : Int
  producer_target_is_input : Bool
  producer_target_index : Int
} derive(Eq, Debug)

///|
pub(all) enum CheckedTaskReferenceIssue {
  InvalidLimits
  InvalidTask
  WorkLimit
  ReferenceLimit
} derive(Eq, Debug)

///|
/// Common projection of the owned graph. No operation-name/step-count profile
/// is selected here; Connector eligibility still interprets the AoA fragment.
pub fn prepare_checked_task_reference(
  graph : CheckedDAG,
  task : Int,
  max_references : Int,
  max_work : Int,
) -> Result[CheckedTaskReference, CheckedTaskReferenceIssue] {
  if max_references < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if task < 0 || task >= graph.owners.length() || graph.targets[task] is None {
    return Err(InvalidTask)
  }
  if graph.data.length() > max_work ||
    graph.control.length() > max_work - graph.data.length() {
    return Err(WorkLimit)
  }
  let owner = graph.owners[task]
  let count = @pipeline.step_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
  if count == 0 {
    return Err(InvalidTask)
  }
  let inputs = []
  let controls = []
  let mut remaining = max_references
  for edge in graph.data {
    if edge.consumer == task {
      if remaining == 0 {
        return Err(ReferenceLimit)
      }
      remaining -= 1
      let (is_input, index) = match edge.target {
        Input(index) => (true, index)
        Step(index) => (false, index)
      }
      inputs.push({
        input: edge.input,
        producer: edge.producer,
        producer_target_is_input: is_input,
        producer_target_index: index,
      })
    }
  }
  for edge in graph.control {
    if edge.consumer == task {
      if remaining == 0 {
        return Err(ReferenceLimit)
      }
      remaining -= 1
      controls.push(edge.predecessor)
    }
  }
  let mut source_stage = None
  for stage_index in 0..<@checked.unit_count(graph.program) {
    if @checked.unit_pipeline(graph.program, stage_index) is Some(pipeline) &&
      physical_equal(pipeline, @lower.pipeline(@lower.bound_preparation(owner))) {
      source_stage = Some(stage_index)
      break
    }
  }
  guard source_stage is Some(stage_index) &&
    graph.targets[task] is Some(Step(output_step)) else {
    return Err(InvalidTask)
  }
  let identity = @checked.source_identity(graph.program)
  let stage = @context.program_identity_stage_at(identity, stage_index).unwrap()
  Ok({
    graph,
    task,
    target: Step(output_step),
    identity: {
      task,
      program_definition_cid: @context.program_identity_definition_cid(identity),
      program_parameters_cid: @context.program_identity_parameter_values_cid(
        identity,
      ),
      unit_definition_cid: @checked.unit_definition_cid(
        graph.program,
        stage_index,
      ).unwrap(),
      unit_parameters_cid: @context.stage_identity_parameter_values_cid(stage),
      unit_contracts_cid: @checked.unit_contracts_cid(
        graph.program,
        stage_index,
      ).unwrap(),
      output_step,
      inputs,
      controls,
    },
  })
}

///|
/// Copy only bounded metadata; callers cannot mutate the owned reference.
pub fn checked_task_identity(
  value : CheckedTaskReference,
) -> CheckedTaskIdentity {
  {
    ..value.identity,
    inputs: value.identity.inputs.copy(),
    controls: value.identity.controls.copy(),
  }
}

///|
/// Equal descriptors are not a substitute for an exact bound producer. This
/// checks the owner/target and present use conditions, not DAG dispatch or
/// completion of a particular attempt (the common publication boundary does).
pub fn checked_task_output_matches(
  value : CheckedTaskReference,
  output : @execution.CompletedOutput,
) -> Bool {
  @execution.completed_output_matches_port(
    output,
    value.graph.owners[value.task],
    value.target,
  )
}
