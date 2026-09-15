///|
/// Check with definition-level evidence selected by authored Stage names and
/// typed limit uses. The compiler binds these inputs and expands actual producer
/// occurrences; no visit arrays or mixed-limit ordinals are accepted here.
/// Evidence binding is part of this call's compilation work, not execution.
pub fn check_with_evidence(
  program : @syntax.Program,
  environment : @environment.WireEnvironment,
  supplied : @decode.Cursor?,
  evidence : Array[@context.StageCapacityInput],
  expression_profiles : @context.ExpressionProfiles,
  operation_profiles : @context.PureOperationProfiles,
  limits : SourceLimits,
  max_work~ : Int,
  max_bytes~ : Int,
  max_nodes~ : Int,
  max_depth~ : Int,
  numeric_profile? : @numeric.Profile? = None,
  calendar? : @environment.SelectedCalendarProfile? = None,
  text_rank? : @environment.SelectedTextRankProfile? = None,
) -> CheckedProgram raise LocalConstructionFailure {
  if max_work < 0 || max_bytes < 0 || max_nodes < 0 || max_depth < 0 {
    raise InvalidLimits
  }
  let inputs = match
    @context.bind_capacity_inputs(program, evidence, max_work) {
    Ok(value) => value
    Err(issue) => raise CapacityInputs(issue)
  }
  check(
    program,
    environment,
    supplied,
    [],
    expression_profiles,
    operation_profiles,
    limits,
    max_work=max_work - @context.capacity_inputs_work(inputs),
    max_bytes~,
    max_nodes~,
    max_depth~,
    numeric_profile~,
    calendar~,
    text_rank~,
    capacity_inputs=Some(inputs),
  )
}
