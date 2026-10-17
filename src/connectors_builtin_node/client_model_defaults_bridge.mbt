///|
/// Private actual-runtime DATA bridge. The Host retains its original Provider
/// registration/configuration; none of these projections issues authority.
#export_name("clientProgramReadInstalledModelDefaults")
pub fn client_program_read_installed_model_defaults(
  provider_id : String,
  installation_wire : String,
  configuration_contract_wire : String,
  configuration_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_members : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientModelProviderDefaults,
  @publication_host.ClientModelProviderDefaultsIssue,
] {
  @publication_host.read_client_model_provider_defaults(
    provider_id,
    installation_wire,
    configuration_contract_wire,
    configuration_wire,
    { max_bytes, max_nodes, max_depth, max_members, },
    max_work,
  )
}

///|
#export_name("clientProgramInstalledModelDefaultsBinding")
pub fn client_program_installed_model_defaults_binding(
  value : @publication_host.ClientModelProviderDefaults,
) -> @publication.RunEvidenceValue {
  @publication_host.client_model_provider_defaults_binding(value)
}

///|
#export_name("clientProgramInstalledModelDefaultsUsage")
pub fn client_program_installed_model_defaults_usage(
  value : @publication_host.ClientModelProviderDefaults,
) -> (Int, Int, Int) {
  @publication_host.client_model_provider_defaults_usage(value)
}

///|
#export_name("clientProgramResolveInstalledModelDefaults")
pub fn client_program_resolve_installed_model_defaults(
  value : @publication_host.ClientModelProviderDefaults,
  selected_model : String?,
  task_max_output_tokens : Int64?,
  max_work : Int,
) -> Result[
  @check_environment.ResolvedModelProviderDefaults,
  @check_environment.ModelProviderDefaultsResolutionIssue,
] {
  @publication_host.resolve_client_model_provider_defaults(
    value, selected_model, task_max_output_tokens, max_work,
  )
}

///|
#export_name("clientProgramInstalledModelDefaultsGeneration")
pub fn client_program_installed_model_defaults_generation(
  value : @publication_host.ClientModelProviderDefaults,
  resolved : @check_environment.ResolvedModelProviderDefaults,
) -> @check_environment.ModelGeneration? {
  @publication_host.client_model_provider_defaults_generation(value, resolved)
}
