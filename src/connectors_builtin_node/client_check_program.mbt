///|
// Existing Node ABI forwards to the same portable Host check projection.
// No check finding, opaque namespace, contract or runnable decision is copied.

///|
#export_name("clientProgramCheckProgram")
pub fn client_program_check_program(
  document : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  parameters : String?,
  context_ref : String,
  program_revision : String,
  parameters_revision : String?,
  correlation_ref : String,
  scope : String,
  selector_namespace : ClientCheckSourceSelectorNamespace?,
) -> String {
  @local_preparation.client_program_check_program(
    document, environment, visible_publication, parameters, context_ref, program_revision,
    parameters_revision, correlation_ref, scope, selector_namespace,
  )
}
