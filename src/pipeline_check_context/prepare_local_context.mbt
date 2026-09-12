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
/// Use the Environment retained by Local source preparation for policy selection,
/// Stage capacity construction, wiring and input correspondence. This is not
/// full source-admission accounting, source request resolution or CheckedProgram.
pub fn prepare_local_context(
  prepared : @stage_results.PreparedLocalSource,
  materials : Array[Array[CapacityMaterial]],
  limits : LocalContextLimits,
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
) -> Result[SelectedPolicyContext, LocalContextIssue] {
  let caps = limits.stages
  if caps.max_work < 0 ||
    caps.max_text_bytes < 0 ||
    caps.max_name_bytes < 0 ||
    caps.max_input_work < 0 ||
    caps.max_operand_work < 0 ||
    limits.max_policy_bytes < 0 ||
    limits.max_policy_nodes < 0 ||
    limits.max_policy_depth < 0 ||
    limits.max_local_input_nodes < 0 {
    return Err(InvalidLimits)
  }
  let wiring = @stage_results.local_source_wiring(prepared)
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
  let stages = match
    prepare_local_stage_contexts(
      prepared,
      materials,
      @environment.capacity_policy(capacity),
      { ..caps, max_work: remaining_work, max_text_bytes: remaining_text, },
      proof_owners~,
      input_owners~,
    ) {
    Ok(v) => v
    Err(e) => return Err(Stages(e))
  }
  let wired = match
    attach_result_wiring(
      stages,
      wiring,
      max_work=remaining_work,
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
    Ok(v) => Ok(v)
    Err(e) => Err(Selection(e))
  }
}
