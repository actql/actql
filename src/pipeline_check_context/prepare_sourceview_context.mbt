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
  calendar? : @environment.SelectedCalendarProfile? = None,
  capacity_inputs? : ProgramCapacityInputs? = None,
  model_tasks? : @environment.ModelTasks? = None,
  derived_capacity_limits? : @wire.Limits? = None,
) -> Result[SelectedPolicyContext, SourceViewContextIssue] {
  let original = match
    prepare_sourceview_context_input(
      views,
      locals,
      source_limits,
      limits,
      calendar~,
      model_tasks~,
    ) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  prepare_sourceview_context_from_input(
    original,
    supplied,
    materials,
    proof_owners~,
    input_owners~,
    capacity_inputs~,
    derived_capacity_limits~,
  )
}

///|
/// One original Context entrance, not a Resource Owner or successful Context.
/// Its selected typed limits and original registration gathering are retained
/// privately; later topology/binding/Stage constructors still need backing.
struct SourceViewContextInput {
  program : SourceViewProgramInput
  limits : LocalContextLimits
}

///|
/// Borrow the SAME source, not a replacement identity or successful Context.
pub fn sourceview_context_input_source(
  original : SourceViewContextInput,
) -> @stages.Source {
  original.program.source
}

///|
/// Original completed entrance work, excluding its already retained view
/// registration prefix. Missing failed entrance Usage is handled separately.
pub fn sourceview_context_input_work(original : SourceViewContextInput) -> Int {
  original.program.extra - original.program.prior
}

///|
/// Invalidate only this original pure continuation after its constructor has
/// unwound. Borrowed Source/Context data and physical backing remain distinct.
pub fn retire_sourceview_context_input(
  original : SourceViewContextInput,
) -> Unit {
  if original.program.topology is Reading(read) {
    @stage_results.clear_local_program_read(read)
  }
  original.program.topology = Retired
}

///|
pub fn prepare_sourceview_context_input(
  views : @sourceviews.PipelineInputs,
  locals : @local_inputs.ProgramEnvironmentInputs,
  source_limits : @stage_results.LocalProgramLimits,
  limits : LocalContextLimits,
  calendar? : @environment.SelectedCalendarProfile? = None,
  model_tasks? : @environment.ModelTasks? = None,
) -> Result[SourceViewContextInput, SourceViewContextIssue] {
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
  match
    prepare_sourceview_program_input(
      views,
      locals,
      source_limits,
      calendar~,
      model_tasks~,
    ) {
    Err(issue) => Err(Program(issue))
    Ok(program) => Ok({ program, limits, })
  }
}

///|
/// SAME completed entrance. Calendar and registration gathering are not
/// repeated. Binding reuse still applies only to the original declarations,
/// supplied Cursor and original compatible limits at its existing owner.
pub fn prepare_sourceview_context_from_input(
  original : SourceViewContextInput,
  supplied : @decode.Cursor?,
  materials : Array[Array[CapacityMaterial]],
  proof_owners? : Array[Array[(Int, Int, Int)]]? = None,
  input_owners? : Array[Array[(Int, Int, Int, Int)]]? = None,
  capacity_inputs? : ProgramCapacityInputs? = None,
  derived_capacity_limits? : @wire.Limits? = None,
) -> Result[SelectedPolicyContext, SourceViewContextIssue] {
  let program = original.program
  let { views, limits: source_limits, prior, .. } = program
  let limits = original.limits
  let (wiring, _, extra) = match
    finish_sourceview_program_input_owned(program, check_only=false) {
    Err(issue) => return Err(Program(issue))
    Ok((Publication(wiring), usage, extra)) => (wiring, usage, extra)
    Ok(_) => abort("mixed preparation modes")
  }
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
      capacity_inputs~,
      derived_capacity_limits~,
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

///|
/// Only the original preflight/empty staging collections. No Pipeline, binding
/// or Result constructor runs here. Back this entrance before calling it.
pub fn begin_sourceview_context_topology_read(
  original : SourceViewContextInput,
) -> Result[@stage_results.LocalProgramRead, SourceViewContextIssue] {
  begin_sourceview_program_topology_read(original.program).map_err(issue => {
    Program(issue)
  })
}

///|
/// Borrow the SAME selected reader. A cleared/taken read is never restarted.
pub fn sourceview_context_topology_read(
  original : SourceViewContextInput,
) -> @stage_results.LocalProgramRead? {
  match original.program.topology {
    Reading(read) => Some(read)
    _ => None
  }
}

///|
/// Entry owns only the original Stage-count work. Local environment work was
/// admitted at its original constructor; the read retains that exact prefix.
pub fn sourceview_context_topology_entry_work_bound(
  original : SourceViewContextInput,
) -> Int? {
  guard original.program.topology is Ready else { return None }
  Some(@stages.stage_count(original.program.source))
}
