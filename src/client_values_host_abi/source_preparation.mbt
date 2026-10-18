///|
/// Public source remains inside this ABI's existing preparation namespace.
#export_name("clientValuesHostPrepareSourceProgram")
pub fn client_values_host_prepare_source_program(
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : String,
) -> Result[@local.LocalSourceComputation, @local.LocalSourceComputationIssue] {
  @local.prepare_local_source_computation(intent, environment, publication)
}

///|
#export_name("clientValuesHostSourceProgramKind")
pub fn client_values_host_source_program_kind(value : @local.LocalSourceComputation) -> String {
  match @local.local_source_computation_preparation(value) {
    Pure(_) => "effect_free"
    Effect(_) => "effect"
  }
}

///|
#export_name("clientValuesHostSourceProgramPure")
pub fn client_values_host_source_program_pure(value : @local.LocalSourceComputation) -> @host.PreparedClientProgram? {
  match @local.local_source_computation_preparation(value) {
    Pure(prepared) => Some(prepared)
    Effect(_) => None
  }
}

///|
#export_name("clientValuesHostSourceProgramEffect")
pub fn client_values_host_source_program_effect(value : @local.LocalSourceComputation) -> @host.PreparedClientEffectComputation? {
  match @local.local_source_computation_preparation(value) {
    Pure(_) => None
    Effect(prepared) => Some(prepared)
  }
}

///|
#export_name("clientValuesHostSourceProgramOriginals")
pub fn client_values_host_source_program_originals(value : @local.LocalSourceComputation) -> Array[String] {
  let (wire, intent, environment, publication) = @local.local_source_computation_originals(value)
  [wire, intent, environment, publication]
}

///|
#export_name("clientValuesHostSourceProgramDocument")
pub fn client_values_host_source_program_document(value : @local.LocalSourceComputation) -> String {
  @local.local_source_computation_material(value).0
}

///|
#export_name("clientValuesHostSourceProgramParameters")
pub fn client_values_host_source_program_parameters(value : @local.LocalSourceComputation) -> String? {
  @local.local_source_computation_material(value).1
}

///|
#export_name("clientValuesHostSourceProgramInput")
pub fn client_values_host_source_program_input(value : @local.LocalSourceComputation) -> Array[String] {
  let (document, format, _) = @local.local_source_computation_source(value)
  [document, format]
}

///|
#export_name("clientValuesHostSourceProgramDeclarations")
pub fn client_values_host_source_program_declarations(value : @local.LocalSourceComputation) -> String? {
  @local.local_source_computation_source(value).2
}

///|
#export_name("clientValuesHostSourceProgramRequest")
pub fn client_values_host_source_program_request(value : @local.LocalSourceComputation,
  intent : @host.ClientSubmittedIntent, environment : @checked.CheckEnvironment,
  authority_scope_cid : String, request_id : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  if !@local.local_source_computation_matches(value, intent, environment) {
    return Err(IdentityMismatch)
  }
  @local.local_source_computation_request(value, authority_scope_cid, request_id)
}
