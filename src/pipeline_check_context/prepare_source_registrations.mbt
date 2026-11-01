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
  let read = match
    begin_source_registration(
      source,
      catalog,
      limits,
      max_inputs~,
      max_views~,
      max_order_keys~,
    ) {
    Err(issue) => return Err(issue)
    Ok(read) => read
  }
  while true {
    match advance_source_registration(read) {
      RegistrationComplete | RegistrationFailed =>
        return take_source_registration_result(read).unwrap()
      RegistrationCollect
      | RegistrationSelect
      | RegistrationPipeline
      | RegistrationLocal => ()
      RegistrationTransferred | RegistrationRetired =>
        abort("unexposed original registration read cannot retire externally")
    }
  } nobreak {
    abort("original registration advancement returns at a terminal phase")
  }
}
