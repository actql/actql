///|
pub enum SourceRegistrationIssue {
  InvalidLimits
  Declarations(@source_inputs.Issue)
  Selection(@sourceviews.Issue)
  Registration(@sourceviews.PipelineIssue)
  LocalInputs(@local_inputs.PrepareEnvironmentIssue)
}

///|
/// Select connector declarations and prepare mixed input registrations from one
/// Source and admitted Catalog. Catalog/Environment admission precedes this
/// boundary; request validation and acquired data checks do not occur here.
pub fn prepare_source_registrations(
  source : @stages.Source,
  catalog : @environment.SourceRequestContracts,
  limits : @local_inputs.Limits,
  max_inputs~ : Int,
  max_views~ : Int,
  max_order_keys~ : Int,
) -> Result[
  (@sourceviews.PipelineInputs, @local_inputs.ProgramEnvironmentInputs),
  SourceRegistrationIssue,
] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 ||
    max_inputs < 0 ||
    max_views < 0 ||
    max_order_keys < 0 {
    return Err(InvalidLimits)
  }
  let inputs = match
    @source_inputs.collect(source, {
      max_work: limits.max_work,
      max_order_keys,
    }) {
    Ok(v) => v
    Err(e) => return Err(Declarations(e))
  }
  let resolved = match
    @sourceviews.resolve(inputs, catalog, {
      max_work: limits.max_work,
      max_inputs,
      max_views,
    }) {
    Ok(v) => v
    Err(e) => return Err(Selection(e))
  }
  let views = match
    @sourceviews.prepare_pipeline_inputs(resolved, limits.max_work) {
    Ok(v) => v
    Err(e) => return Err(Registration(e))
  }
  // Registration includes the collection/selection prefix. The remaining
  // allowance bounds Local snapshot preparation under its pass conventions.
  let locals = match
    @local_inputs.prepare_environment(
      source,
      @sourceviews.pipeline_environment(views),
      {
        ..limits,
        max_work: limits.max_work - @sourceviews.pipeline_inputs_work(views),
      },
      sourceviews=Some(inputs),
    ) {
    Ok(v) => v
    Err(e) => return Err(LocalInputs(e))
  }
  Ok((views, locals))
}
