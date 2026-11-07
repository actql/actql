///|
// Existing Node ABI forwards to the same portable Host check projection.
// No check finding, opaque namespace, contract or runnable decision is copied.

///|
pub type ClientCheckSourceSelectorRange = @local_preparation.ClientCheckSourceSelectorRange

///|
pub type ClientCheckSourceSelectorNamespace = @local_preparation.ClientCheckSourceSelectorNamespace

///|
#export_name("clientProgramCheckSourceSelectorRange")
pub fn client_program_check_source_selector_range(
  environment : @program_check.CheckEnvironment,
  registrations : Array[@program_check.CheckEnvironment],
) -> ClientCheckSourceSelectorRange? {
  @local_preparation.client_program_check_source_selector_range(
    environment, registrations,
  )
}

///|
#export_name("clientProgramCheckSourceSelectorNamespace")
pub fn client_program_check_source_selector_namespace(
  range : ClientCheckSourceSelectorRange,
  namespace_name : String,
  configuration_revision : String,
  context_ref : String,
  program_revision : String,
) -> ClientCheckSourceSelectorNamespace? {
  @local_preparation.client_program_check_source_selector_namespace(
    range, namespace_name, configuration_revision, context_ref, program_revision,
  )
}

///|
#export_name("clientProgramCheckPreparedSourceSelectorRange")
pub fn client_program_check_prepared_source_selector_range(
  environment : @program_check.CheckEnvironment,
  prepared : @source_publication.PreparedPublishedQueryEnvironment,
  registrations : Array[@program_check.CheckEnvironment],
) -> ClientCheckSourceSelectorRange? {
  @local_preparation.client_program_check_prepared_source_selector_range(
    environment, prepared, registrations,
  )
}
