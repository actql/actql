///|
// Existing Node ABI forwards to the same portable Host check projection.
// No check finding, opaque namespace, contract or runnable decision is copied.

///|
pub type ClientCheckSourceNamespace = @local_preparation.ClientCheckSourceNamespace

///|
#export_name("clientProgramCheckSourceNamespace")
pub fn client_program_check_source_namespace(
  environment : @program_check.CheckEnvironment,
  publication : String,
  namespace_name : String,
  configuration_revision : String,
  context_ref : String,
  source_revision : String,
) -> ClientCheckSourceNamespace? {
  @local_preparation.client_program_check_source_namespace(
    environment, publication, namespace_name, configuration_revision, context_ref,
    source_revision,
  )
}
