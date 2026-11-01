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

///|
/// Borrow the live Request's original CheckOutcome for its current audience.
/// No opaque result layout, checker or retired report is reconstructed in JS.
#export_name("clientProgramProjectRequestCheckOutcome")
pub fn client_program_project_request_check_outcome(
  parent : @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  input : ClientLocalPreparationInputOriginal,
  terminal : @client_local_host.ClientRequestTerminalIssue,
  visible_publication : String,
  context_ref : String,
  input_kind : String,
  input_revision : String,
  input_bytes : Int,
  declarations_revision : String?,
  declarations_bytes : Int,
  parameters_revision : String?,
  parameters_bytes : Int,
  correlation_ref : String,
  selector_namespace : ClientCheckSourceSelectorNamespace?,
) -> Result[String?, @client_local_host.ClientRequestPreparationIssue] {
  @client_local_host.project_request_check_outcome(
    parent, input, terminal, visible_publication, context_ref, input_kind, input_revision,
    input_bytes, declarations_revision, declarations_bytes, parameters_revision,
    parameters_bytes, correlation_ref, selector_namespace,
  )
}
