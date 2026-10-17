///|
// Existing Node ABI forwards to the same portable Host check projection.
// No check finding, opaque namespace, contract or runnable decision is copied.

///|
#export_name("clientProgramCheckSource")
pub fn client_program_check_source(
  document : String,
  format : String,
  environment : @program_check.CheckEnvironment,
  visible_publication : String,
  declarations : String?,
  parameters : String?,
  context_ref : String,
  source_revision : String,
  declarations_revision : String?,
  parameters_revision : String?,
  correlation_ref : String,
  scope : String,
  source_namespace : ClientCheckSourceNamespace?,
) -> String {
  @local_preparation.client_program_check_source(
    document, format, environment, visible_publication, declarations, parameters,
    context_ref, source_revision, declarations_revision, parameters_revision, correlation_ref,
    scope, source_namespace,
  )
}

///|
#export_name("clientProgramCheckUnavailable")
pub fn client_program_check_unavailable(correlation_ref : String) -> String {
  @local_preparation.client_program_check_unavailable(correlation_ref)
}

///|
#export_name("clientProgramCheckCompilerIdentity")
pub fn client_program_check_compiler_identity() -> String {
  @local_preparation.client_program_check_compiler_identity()
}
