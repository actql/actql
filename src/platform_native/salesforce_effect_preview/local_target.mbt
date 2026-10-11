///|
/// Physical response and its separate checked projection. The Host must retain
/// exact response/use/request originals through existing capture custody before
/// treating observation preparation as durable. A projection failure does not
/// discard response bytes or turn a sent use into a fresh observation permit.
pub struct NativeLocalSalesforceTargetObservation {
  request : @catalog.LocalTargetReadRequest
  response : @resource.NativeCredentialResponse
  response_sha256 : String
  projection : Result[
    (@catalog.TargetObservation, @catalog.TargetPreviewRow),
    NativeSalesforcePreviewIssue,
  ]
}

///|
fn local_target_read_matches_preparation_scope(
  request : @catalog.LocalTargetReadRequest,
  scope : @credential.LocalPreparationCredentialScope,
  credential_org_id : String,
) -> Bool {
  let binding = @catalog.local_target_read_request_binding(request)
  let fence = @credential.local_preparation_fence_fields(
    scope.preparation_fence,
  )
  binding.account_configuration_cid == scope.account_configuration_cid &&
  binding.account_id == scope.account_id &&
  binding.authority_scope_cid == scope.authority_scope_cid &&
  binding.client_request_intent_cid == fence.client_request_intent_cid &&
  binding.client_request_scope_cid == fence.client_request_scope_cid &&
  binding.client_request_scope_cid == scope.submission_scope_cid &&
  binding.connector_registration == scope.connector_registration &&
  binding.connector_revision == scope.connector_revision &&
  binding.host_adoption_cid == scope.host_adoption_cid &&
  binding.org_id == credential_org_id &&
  binding.principal == scope.principal &&
  binding.resource_origin == scope.resource_origin &&
  binding.run_invocation_cid == scope.run_invocation_cid &&
  binding.run_invocation_cid == fence.run_invocation_cid &&
  scope.operation == "salesforce:record:observe" &&
  scope.operation_occurrence_cid == fence.operation_occurrence_cid &&
  scope.unit_definition_cid == fence.unit_definition_cid &&
  scope.request_method == "GET" &&
  scope.request_path == @catalog.local_target_read_request_path(request) &&
  scope.request_cid == @catalog.local_target_read_request_cid(request) &&
  scope.request_body_cid ==
  "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}

///|
/// Observe the same checked Local update target under its separate GET grant.
/// Trusted Host assembly supplies the original Work guard and independently
/// current read/issuer decisions; this does not approve a Preview or execute
/// a mutation. It uses the same credential claim/transport and Catalog target
/// projection Owners as Remote, without a Site or Dispatch identity.
pub fn observe_native_local_salesforce_effect_target(
  service : @resource.NativeCredentialResourceService,
  grant : @credential.LocalPreparationCredentialGrant,
  use_id : String,
  scope : @credential.LocalPreparationCredentialScope,
  credential_org_id : String,
  request : @catalog.LocalTargetReadRequest,
  current_catalog : @catalog.CatalogObservation,
  limits : @catalog.TargetObservationLimits,
  current : () -> Bool,
) -> Result[
  NativeLocalSalesforceTargetObservation,
  NativeSalesforcePreviewIssue,
] {
  if !native_salesforce_target_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let candidate = @catalog.local_target_read_request_candidate(request)
  if !local_target_read_matches_preparation_scope(
      request, scope, credential_org_id,
    ) ||
    !@catalog.catalog_observation_matches_local_binding(
      current_catalog,
      @catalog.local_target_read_request_binding(request),
    ) {
    return Err(ForeignScope)
  }
  match @catalog.recheck_single_write_request(candidate, current_catalog) {
    Ok(_) => ()
    Err(issue) => return Err(Catalog(issue))
  }
  let response = match
    @resource.call_native_local_preparation_credential_resource_guarded_request_at_path(
      service,
      grant,
      use_id,
      scope,
      @catalog.local_target_read_request_path(request),
      current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  // Keep physical evidence even when provider data fails semantic projection.
  // No additional copy, response re-open, grant renewal or send is performed.
  Ok(native_local_target_observation_from_response(request, response, limits))
}

///|
fn native_local_target_observation_from_response(
  request : @catalog.LocalTargetReadRequest,
  response : @resource.NativeCredentialResponse,
  limits : @catalog.TargetObservationLimits,
) -> NativeLocalSalesforceTargetObservation {
  {
    request,
    response,
    response_sha256: @catalog.catalog_response_sha256(response.body),
    projection: native_salesforce_target_preview(
      @catalog.local_target_read_request_candidate(request),
      response,
      limits,
    ).map(value => (value.1, value.2)),
  }
}
