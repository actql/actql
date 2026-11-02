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
  publication_environment? : @publication.PreparedPublishedQueryEnvironment? = None,
) -> Result[LocalSourceComputation, LocalSourceComputationIssue] {
  @host.prepare_client_source_computation(
    intent,
    environment,
    publication,
    public_primary~,
    publication_environment~,
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

///|
/// Preserve the same existing Pure preparation at the installed Host handoff.
/// The source, intent and environment must be the original triple; equal
/// serialized input cannot replace them. Effect computations remain under
/// their own owner and cannot acquire a Pure preparation through this view.
/// This performs no lowering, checking, Run issuance or executable restore.
pub fn local_source_pure_submitted_preparation(
  source : LocalSourceComputation,
  intent : @host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
) -> LocalSubmittedPreparation? {
  if !local_source_computation_matches(source, intent, environment) {
    return None
  }
  let prepared = match local_source_computation_preparation(source) {
    Pure(prepared) => prepared
    Effect(_) => return None
  }
  let (authored, _, _) = local_source_computation_source(source)
  let (document, _) = local_source_computation_material(source)
  Some({ intent, input: { prepared, original: Aql(authored), document, }, })
}
