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
  collected_inputs_out? : Ref[@source_inputs.Inputs?]? = None,
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
      RegistrationComplete | RegistrationFailed => {
        // Borrow this same reader's collection before normal handoff clears
        // its aliases. No collector, resolver or binding read is repeated.
        if collected_inputs_out is Some(output) {
          output.val = source_registration_collected_inputs(read)
        }
        return take_source_registration_result(read).unwrap()
      }
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
