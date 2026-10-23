///|
/// Check with definition-level evidence selected by authored Stage names and
/// typed limit uses. The compiler binds these inputs and expands actual producer
/// occurrences; no visit arrays or mixed-limit ordinals are accepted here.
/// Evidence binding is part of this call's compilation work, not execution.
pub fn check_parsed_with_evidence(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  source_catalog? : PreparedSourceCatalog? = None,
) -> CheckOutcome {
  checking_outcome(program, environment, () => {
    construct_parsed(
      program,
      environment,
      supplied,
      evidence,
      limits,
      source_catalog~,
    )
  })
}

///|
fn construct_parsed(
  program : @syntax.Program,
  environment : CheckEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  limits : CheckLimits,
  effect_headers? : @syntax.EffectHeaders? = None,
  source_catalog? : PreparedSourceCatalog? = None,
) -> CheckedProgram raise LocalConstructionFailure {
  if !compile_limits_valid(limits.compilation) {
    raise InvalidLimits
  }
  match @syntax.validate_reuse(program, limits.input) {
    Ok(_) => ()
    Err(issue) => raise Program(issue)
  }
  if source_catalog is Some(prepared) &&
    !physical_equal(prepared.environment, environment) {
    raise Environment(ForeignPreparedCatalog)
  }
  let limits = limits.compilation
  let inputs = match
    @context.bind_capacity_inputs(program, evidence, limits.work) {
    Ok(value) => value
    Err(issue) => raise CapacityInputs(issue)
  }
  check(
    program,
    environment.wire,
    supplied,
    [],
    environment.expressions,
    environment.operations,
    compile_source_limits(limits),
    max_work=limits.work - @context.capacity_inputs_work(inputs),
    max_bytes=limits.artifacts.bytes,
    max_nodes=limits.artifacts.nodes,
    max_depth=limits.artifacts.depth,
    numeric_profile=environment.numeric,
    calendar=environment.calendar,
    text_rank=environment.text_rank,
    capacity_inputs=Some(inputs),
    effect_headers~,
    graph=environment.graph,
    model_tasks=environment.model_tasks,
    request_value_policies=environment.request_value_policies,
    source_catalog~,
  )
}
