///|
pub enum SourceViewContextIssue {
  InvalidLimits
  Program(SourceViewProgramIssue)
  Binding(@stage_results.LocalSourceIssue)
  Context(LocalContextIssue)
}

///|
/// Prepare topology, effective Parameters and contexts from one admitted pair
/// of registrations. No independent wiring, binding result or successful
/// capacity application is accepted. Catalog admission and complete Program
/// closure remain separate from this context preparation.
pub fn prepare_sourceview_context(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  supplied : @decode.Cursor?,
  materials : Array[Array[CapacityMaterial]],
  source_limits : @stage_results.LocalProgramLimits,
  limits : LocalContextLimits,
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
) -> Result[SelectedPolicyContext, SourceViewContextIssue] {
  if !local_context_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let source_limits = {
    ..source_limits,
    max_work: Int::min(source_limits.max_work, limits.stages.max_work),
    max_text_bytes: Int::min(
      source_limits.max_text_bytes,
      limits.stages.max_text_bytes,
    ),
  }
  let (wiring, _, extra) = match
    prepare_sourceview_program_internal(views, locals, source_limits) {
    Ok(v) => v
    Err(e) => return Err(Program(e))
  }
  let prior = @sourceviews.pipeline_inputs_work(views)
  // Both prefixes were bounded by topology preparation. The binder already
  // retains its own topology costs, but neither of these external costs.
  let prepared = match
    @stage_results.bind_prepared_program(wiring, supplied, {
      ..source_limits,
      max_work: source_limits.max_work - extra - prior,
    }) {
    Ok(v) => v
    Err(e) => return Err(Binding(e))
  }
  let checked = match
    prepare_local_context(
      prepared,
      materials,
      {
        ..limits,
        stages: { ..limits.stages, max_work: limits.stages.max_work - extra, },
      },
      sourceviews=Some(views),
      proof_owners~,
      input_owners~,
    ) {
    Ok(v) => v
    Err(e) => return Err(Context(e))
  }
  // Context joining already charges the retained view-registration prefix.
  // Add only the owned gathering/correspondence work it does not repeat.
  Ok({
    ..checked,
    usage: { ..checked.usage, work: checked.usage.work + extra, },
  })
}
