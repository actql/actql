///|
// Existing Node ABI forwards to the same portable Host check projection.
// No check finding, opaque namespace, contract or runnable decision is copied.

///|
#export_name("clientProgramCheckContextIdentity")
pub fn client_program_check_context_identity(
  environment : @program_check.CheckEnvironment,
) -> String {
  @local_preparation.client_program_check_context_identity(environment)
}
