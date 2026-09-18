///|
/// Export selected immutable requirements, not this evaluator's preparation.
/// The neutral constructor is also available without a Local execution engine.
pub fn generated_sequence_requirements(
  generated : GeneratedSequence,
  max_entries : Int,
) -> Result[@lower.SequenceRequirements, @lower.SequenceRequirementsIssue] {
  if max_entries < 0 || generated.contexts.length() > max_entries {
    return Err(InvalidLimits)
  }
  let fragments = []
  for context in generated.contexts {
    let requirement = match
      @lower.prepare_fragment_enforcement(
        context.fragment.candidate.material.request.request,
        context.limits,
        context.physical.max_body_bytes,
        context.physical.max_body_nodes,
        context.physical.max_body_depth,
        context.root_result_bytes,
        context.all_expression_roots,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    fragments.push(requirement)
  }
  @lower.prepare_sequence_requirements(
    generated.sequence,
    fragments,
    generated.join_ceilings,
    max_entries,
  )
}

///|
/// Match actual enforcement to the exact selected requests. Equal JSON, owner
/// CID or coincidentally equal ceilings cannot substitute for owned requests.
pub fn generated_satisfies_requirements(
  generated : GeneratedSequence,
  required : @lower.SequenceRequirements,
) -> Bool {
  if !physical_equal(
      generated.sequence,
      @lower.sequence_requirements_sequence(required),
    ) ||
    generated.contexts.length() !=
    @lower.sequence_requirements_fragment_count(required) {
    return false
  }
  for context in generated.contexts {
    guard @lower.sequence_requirements_fragment_for_step(
        required,
        @lower.kernel_step(context.kernel),
      )
      is Some(expected) else {
      return false
    }
    let actual = context.limits
    let selected = expected.logical
    if !physical_equal(
        context.fragment.candidate.material.request.request,
        expected.request,
      ) ||
      actual.max_input_rows != selected.max_input_rows ||
      actual.max_value_bytes != selected.max_value_bytes ||
      actual.max_live_value_bytes != selected.max_live_value_bytes ||
      actual.max_work != selected.max_work ||
      context.physical.max_body_bytes != expected.measure_bytes ||
      context.physical.max_body_nodes != expected.measure_nodes ||
      context.physical.max_body_depth != expected.measure_depth ||
      context.root_result_bytes != expected.root_result_bytes ||
      context.all_expression_roots != expected.all_expression_roots {
      return false
    }
  }
  if generated.join_ceilings.length() !=
    @lower.sequence_requirements_join_count(required) {
    return false
  }
  for index, ceiling in generated.join_ceilings {
    if @lower.sequence_requirements_join_at(required, index) != Some(ceiling) {
      return false
    }
  }
  true
}
