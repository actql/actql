///|
/// Local and remote callers share the same original Run preparation Owner.
pub type LocalSourceComputation = @host.ClientSourcePreparation

///|
pub type LocalSourceComputationPreparation = @host.ClientSourceProgramPreparation

///|
pub type LocalSourceComputationIssue = @host.ClientSourcePreparationIssue

///|
pub fn prepare_local_source_computation(
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
  publication : String,
  public_primary? : Bool = false,
) -> Result[LocalSourceComputation, LocalSourceComputationIssue] {
  @host.prepare_client_source_computation(
    intent,
    environment,
    publication,
    public_primary~,
  )
}

///|
pub fn local_source_computation_preparation(
  value : LocalSourceComputation,
) -> LocalSourceComputationPreparation {
  @host.client_source_computation_preparation(value)
}

///|
pub fn local_source_computation_originals(
  value : LocalSourceComputation,
) -> (String, String, String, String) {
  @host.client_source_computation_originals(value)
}

///|
pub fn local_source_computation_material(
  value : LocalSourceComputation,
) -> (String, String?) {
  @host.client_source_computation_material(value)
}

///|
pub fn local_source_computation_source(
  value : LocalSourceComputation,
) -> (String, String, String?) {
  @host.client_source_computation_source(value)
}

///|
pub fn local_source_computation_matches(
  value : LocalSourceComputation,
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
) -> Bool {
  @host.client_source_computation_matches(value, intent, environment)
}

///|
pub fn local_source_computation_request(
  value : LocalSourceComputation,
  authority_scope_cid : String,
  request_id : String,
) -> Result[@host.ClientRequestIdentity, @host.ClientRequestIdentityIssue] {
  @host.client_source_computation_request(
    value, authority_scope_cid, request_id,
  )
}
