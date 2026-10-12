///|
pub(all) enum ClientRunBindingIssue {
  ChangedIntent
  ForeignRun
} derive(Eq, Debug)

///|
/// The existing admission binding shared by ordinary Run binding and original
/// Submission acceptance. This pure check grants neither acceptance nor work;
/// the journal still persists acceptance in its original transaction.
pub fn validate_client_run_binding(
  request : ClientRequestIdentity,
  prepared : PreparedClientProgram,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientRunBindingIssue] {
  let identity = prepared_client_identity(prepared)
  if !client_compiled_run_matches(compiled, prepared) ||
    client_request_program_cid(request) != identity.program_definition_cid ||
    client_request_parameters_cid(request) != identity.parameter_values_cid {
    return Err(ChangedIntent)
  }
  if check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  Ok(())
}
