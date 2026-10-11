///|
pub(all) enum NativeSalesforcePreviewIssue {
  InvalidLimits
  ForeignScope
  Catalog(@catalog.WriteProjectionIssue)
  Credential(@resource.NativeCredentialResourceIssue)
  Observation(@catalog.TargetObservationIssue)
}

///|
/// Read the real target under its separate observe grant and the credential's
/// locally configured org. The checked request must match the current Catalog,
/// Site scope and installed physical path before I/O. Returned Provider facts
/// confer neither Preview approval nor write authority; the caller still owns
/// whole-Preview admission, input pins, Checkpoint persistence and cleanup.
pub fn observe_native_salesforce_effect_target(
  service : @resource.NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : @resource.NativeCredentialScope,
  credential_org_id : String,
  request : @catalog.SingleWriteRequest,
  current_catalog : @catalog.CatalogObservation,
  limits : @catalog.TargetObservationLimits,
) -> Result[
  (String, @catalog.TargetObservation, @catalog.TargetPreviewRow),
  NativeSalesforcePreviewIssue,
] {
  if !native_salesforce_target_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if @catalog.single_write_request_method(request) != "PATCH" ||
    scope.operation != "salesforce:record:observe" ||
    credential_org_id != @catalog.single_write_request_org_id(request) ||
    !@catalog.single_write_request_matches_site_scope(
      request,
      scope.namespace_id,
      scope.principal,
      scope.environment,
      scope.site_key,
      scope.site_generation,
      scope.connector_registration,
      scope.connector_revision,
      scope.resource_origin,
      scope.run_invocation_cid,
      scope.dispatch_request_cid,
    ) {
    return Err(ForeignScope)
  }
  match @catalog.recheck_single_write_request(request, current_catalog) {
    Ok(_) => ()
    Err(issue) => return Err(Catalog(issue))
  }
  let response = match
    @resource.call_native_credential_resource_at_path(
      service,
      grant,
      use_id,
      scope,
      @catalog.single_write_request_path(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  native_salesforce_target_preview(request, response, limits)
}

///|
fn native_salesforce_target_limits_valid(
  limits : @catalog.TargetObservationLimits,
) -> Bool {
  !(limits.max_bytes < 1 ||
  limits.max_bytes > 1000000 ||
  limits.max_nodes < 1 ||
  limits.max_nodes > 100000 ||
  limits.max_depth < 1 ||
  limits.max_depth > 64 ||
  limits.max_identity_bytes < 1 ||
  limits.max_identity_bytes > 1000000)
}

///|
// Shared projection of the physical original; response retention, whole
// Preview admission and current authority remain with the calling Host Owner.
fn native_salesforce_target_preview(
  request : @catalog.SingleWriteRequest,
  response : @resource.NativeCredentialResponse,
  limits : @catalog.TargetObservationLimits,
) -> Result[
  (String, @catalog.TargetObservation, @catalog.TargetPreviewRow),
  NativeSalesforcePreviewIssue,
] {
  let observation = match
    @catalog.prepare_target_observation(
      request,
      response.status,
      response.body,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let row = match
    @catalog.prepare_observed_target_preview_row(
      request,
      observation,
      limits.max_identity_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  Ok((response.use_cid, observation, row))
}
