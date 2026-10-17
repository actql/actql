///|
/// Original configuration DATA in the existing Model/Host owner. This is not
/// an installed Provider, current configuration, resource profile or grant.
struct ClientModelProviderDefaults {
  binding : @publication.RunEvidenceValue
  profile : @environment.ModelProviderDefaults?
  bytes : Int
  nodes : Int
  work : Int
}

///|
pub(all) enum ClientModelProviderDefaultsIssue {
  InvalidBinding(@publication.RunEvidenceValueIssue)
  InvalidDefaults(@environment.ModelTaskIssueKind)
} derive(Eq, Debug)

///|
/// Admit the same three canonical originals before reading their configuration.
/// The physical Host must separately retain its actual registration/revision
/// and establish currentness; equal bodies alone prove none of those facts.
pub fn read_client_model_provider_defaults(
  provider_id : String,
  installation_wire : String,
  configuration_contract_wire : String,
  configuration_wire : String,
  limits : @environment.Limits,
  max_work : Int,
) -> Result[ClientModelProviderDefaults, ClientModelProviderDefaultsIssue] {
  let binding = match
    issue_client_model_provider_binding(
      provider_id, installation_wire, configuration_contract_wire, configuration_wire,
    ) {
    Ok(value) => value
    Err(issue) => return Err(InvalidBinding(issue))
  }
  match
    @environment.read_model_provider_defaults_configuration(
      @utf8.encode(configuration_wire),
      limits,
      max_work,
    ) {
    Ok((profile, bytes, nodes, work)) =>
      Ok({ binding, profile, bytes, nodes, work, })
    Err(issue) => Err(InvalidDefaults(issue.kind))
  }
}

///|
pub fn client_model_provider_defaults_binding(
  value : ClientModelProviderDefaults,
) -> @publication.RunEvidenceValue {
  value.binding
}

///|
/// Report profile-reader work even without defaults. The existing binding's
/// separate canonical parsing/encoding is not included or claimed free.
pub fn client_model_provider_defaults_usage(
  value : ClientModelProviderDefaults,
) -> (Int, Int, Int) {
  (value.bytes, value.nodes, value.work)
}

///|
pub fn resolve_client_model_provider_defaults(
  value : ClientModelProviderDefaults,
  selected_model : String?,
  task_max_output_tokens : Int64?,
  max_work : Int,
) -> Result[
  @environment.ResolvedModelProviderDefaults,
  @environment.ModelProviderDefaultsResolutionIssue,
] {
  match value.profile {
    None => Err(@environment.DefaultUnavailable)
    Some(original) =>
      @environment.resolve_model_provider_defaults(
        original, selected_model, task_max_output_tokens, max_work,
      )
  }
}

///|
/// A separately read equal configuration is not the original selected pair.
pub fn client_model_provider_defaults_generation(
  value : ClientModelProviderDefaults,
  resolved : @environment.ResolvedModelProviderDefaults,
) -> @environment.ModelGeneration? {
  match value.profile {
    None => None
    Some(original) =>
      @environment.resolved_model_provider_defaults_generation(
        resolved, original,
      )
  }
}
