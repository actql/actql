///|
pub(all) struct LocalContextLimits {
  stages : CapacityStageLimits
  max_policy_bytes : Int
  max_policy_nodes : Int
  max_policy_depth : Int
  max_local_input_nodes : Int
} derive(Eq, Debug)

///|
pub enum LocalContextIssue {
  InvalidLimits
  MissingEnvironment
  BudgetExceeded
  Policy(@environment.CapacityIssue)
  Stages(CapacityStageIssue)
  Wiring(WiringIssue)
  Inputs(PreparedLocalInputsIssue)
  Selection(SelectedPolicyIssue)
}

///|
pub enum LocalProgramContextIssue {
  InvalidLimits
  Source(@stage_results.LocalSourceIssue)
  Context(LocalContextIssue)
}

///|
/// Prepare source-owned Parameters and topology before joining Local contexts.
/// Materials are admitted Host claims and unchecked consumer coordinates, not
/// caller-assembled successful checks. This is not a complete CheckedProgram.
pub fn prepare_local_program_context(
  program : @syntax.Program,
  supplied : @decode.Cursor?,
  environment : @environment.WireEnvironment,
  materials : Array[Array[CapacityMaterial]],
  source_limits : @stage_results.LocalProgramLimits,
  limits : LocalContextLimits,
  max_parameters~ : Int,
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
) -> Result[SelectedPolicyContext, LocalProgramContextIssue] {
  if !local_context_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let prepared = match
    @stage_results.prepare_local_source(
      program,
      supplied,
      max_parameters~,
      {
        ..source_limits,
        max_work: Int::min(source_limits.max_work, limits.stages.max_work),
        max_text_bytes: Int::min(
          source_limits.max_text_bytes,
          limits.stages.max_text_bytes,
        ),
      },
      environment=Some(environment),
    ) {
    Ok(v) => v
    Err(e) => return Err(Source(e))
  }
  match
    prepare_local_context(
      prepared,
      materials,
      limits,
      proof_owners~,
      input_owners~,
    ) {
    Ok(v) => Ok(v)
    Err(e) => Err(Context(e))
  }
}

///|
fn local_context_limits_valid(limits : LocalContextLimits) -> Bool {
  let caps = limits.stages
  caps.max_work >= 0 &&
  caps.max_text_bytes >= 0 &&
  caps.max_name_bytes >= 0 &&
  caps.max_input_work >= 0 &&
  caps.max_operand_work >= 0 &&
  limits.max_policy_bytes >= 0 &&
  limits.max_policy_nodes >= 0 &&
  limits.max_policy_depth >= 0 &&
  limits.max_local_input_nodes >= 0
}

///|
/// Use the Environment retained by Local source preparation for policy selection,
/// Stage capacity construction, wiring and input correspondence. This is not
/// parsing, source request resolution or CheckedProgram. Prepared-source work
/// and text not already retained by its joined branches are charged once.
pub fn prepare_local_context(
  prepared : @stage_results.PreparedLocalSource,
  materials : Array[Array[CapacityMaterial]],
  limits : LocalContextLimits,
  sourceviews? : @sourceviews.PipelineInputs? = None,
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
  capacity_inputs? : ProgramCapacityInputs? = None,
) -> Result[SelectedPolicyContext, LocalContextIssue] {
  let caps = limits.stages
  if !local_context_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if capacity_inputs is Some(_) &&
    (
      !materials.is_empty() ||
      proof_owners is Some(_) ||
      input_owners is Some(_)
    ) {
    return Err(Stages(Inputs(ConflictingInputs)))
  }
  let wiring = @stage_results.local_source_wiring(prepared)
  let (prefix_work, prefix_text) = @stage_results.local_source_context_prefix(
    prepared,
  )
  if prefix_work < 0 ||
    prefix_text < 0 ||
    prefix_work > caps.max_work ||
    prefix_text > caps.max_text_bytes {
    return Err(BudgetExceeded)
  }
  let caps = {
    ..caps,
    max_work: caps.max_work - prefix_work,
    max_text_bytes: caps.max_text_bytes - prefix_text,
  }
  guard @stage_results.wiring_local_environment(wiring) is Some(inputs) else {
    return Err(MissingEnvironment)
  }
  let capacity = match
    @environment.read_capacity(@local_inputs.program_environment(inputs), {
      max_bytes: Int::min(limits.max_policy_bytes, caps.max_text_bytes),
      max_nodes: Int::min(limits.max_policy_nodes, caps.max_work),
      max_depth: limits.max_policy_depth,
    }) {
    Ok(v) => v
    Err(e) => return Err(Policy(e))
  }
  let (bytes, nodes) = @environment.capacity_usage(capacity)
  if nodes >= caps.max_work || bytes > caps.max_text_bytes {
    return Err(BudgetExceeded)
  }
  // Reserve the admitted component and final owner join. bind_capacity_policy
  // accounts these once; all intermediate joins receive the remaining cap.
  let remaining_work = caps.max_work - nodes - 1
  let remaining_text = caps.max_text_bytes - bytes
  let remote_work = match sourceviews {
    Some(views) => @sourceviews.pipeline_inputs_work(views)
    None => 0
  }
  if remote_work > remaining_work {
    return Err(BudgetExceeded)
  }
  let prepared_stages = match capacity_inputs {
    Some(inputs) =>
      prepare_local_stage_contexts_from_inputs(
        prepared,
        inputs,
        @environment.capacity_policy(capacity),
        {
          ..caps,
          max_work: remaining_work - remote_work,
          max_text_bytes: remaining_text,
        },
      )
    None =>
      prepare_local_stage_contexts(
        prepared,
        materials,
        @environment.capacity_policy(capacity),
        {
          ..caps,
          max_work: remaining_work - remote_work,
          max_text_bytes: remaining_text,
        },
        proof_owners~,
        input_owners~,
      )
  }
  let stages = match prepared_stages {
    Ok(v) => v
    Err(e) => return Err(Stages(e))
  }
  let wired = match
    attach_result_wiring(
      stages,
      wiring,
      max_work=remaining_work - remote_work,
      max_text_bytes=remaining_text,
    ) {
    Ok(v) => v
    Err(e) => return Err(Wiring(e))
  }
  let reconciled = match
    attach_prepared_local_inputs(
      wired,
      max_work=remaining_work,
      max_text_bytes=remaining_text,
      max_local_input_nodes=limits.max_local_input_nodes,
      sourceviews~,
    ) {
    Ok(v) => v
    Err(e) => return Err(Inputs(e))
  }
  match
    bind_capacity_policy(
      reconciled,
      capacity,
      max_work=caps.max_work,
      max_text_bytes=caps.max_text_bytes,
      max_policy_nodes=limits.max_policy_nodes,
    ) {
    Ok(v) =>
      Ok({
        ..v,
        usage: {
          ..v.usage,
          work: v.usage.work + prefix_work,
          text_bytes: v.usage.text_bytes + prefix_text,
        },
      })
    Err(e) => Err(Selection(e))
  }
}
