///|
pub(all) enum NativeSalesforceNamedCatalogIssue {
  InvalidCatalogConfiguration
  CatalogScopeMismatch
  MetadataAccessDenied
  MetadataAuthorizationChanged(@resource.NativeCredentialResponse)
  CatalogCredential(@resource.NativeCredentialResourceIssue)
  // Physical response evidence is retained even when it cannot form an
  // authorized Catalog. It does not permit retry with another credential use.
  MetadataReadUnavailable(@resource.NativeCredentialResponse)
  CatalogSyncFailure(
    @catalog.CatalogSyncIssue,
    @resource.NativeCredentialResponse
  )
  CatalogObservationFailure(
    @catalog.CatalogObservationIssue,
    @resource.NativeCredentialResponse
  )
}

///|
fn native_named_catalog_path(
  scope : @resource.NativeCredentialScope,
  binding : @catalog.CatalogObservationBinding,
  credential_org_id : String,
  api_version : String,
  resource_name : String,
) -> Result[String, NativeSalesforceNamedCatalogIssue] {
  if scope.operation != "salesforce:catalog:describe" ||
    credential_org_id != binding.org_id ||
    scope.namespace_id != binding.namespace_id ||
    scope.principal != binding.principal ||
    scope.environment != binding.environment ||
    scope.site_key != binding.site_key ||
    scope.site_generation != binding.site_generation ||
    scope.connector_registration != binding.connector_registration ||
    scope.connector_revision != binding.connector_revision ||
    scope.resource_origin != binding.resource_origin ||
    scope.run_invocation_cid != binding.run_invocation_cid ||
    scope.dispatch_request_cid != binding.dispatch_request_cid {
    return Err(CatalogScopeMismatch)
  }
  if binding.connection_revision.is_empty() ||
    binding.sync_occurrence.is_empty() ||
    api_version.length() < 4 ||
    api_version.length() > 32 ||
    api_version[0] != 'v' ||
    api_version[1] < '1' ||
    api_version[1] > '9' {
    return Err(InvalidCatalogConfiguration)
  }
  let mut dot = false
  let mut fractional_digits = 0
  for index in 2..<api_version.length() {
    let value = api_version[index]
    if value == '.' && !dot {
      dot = true
    } else if value >= '0' && value <= '9' {
      if dot {
        fractional_digits += 1
      }
    } else {
      return Err(InvalidCatalogConfiguration)
    }
  }
  if !dot ||
    fractional_digits == 0 ||
    @catalog.begin_named_catalog_sync([resource_name]) is Err(_) {
    return Err(InvalidCatalogConfiguration)
  }
  Ok(
    "/services/data/" + api_version + "/sobjects/" + resource_name + "/describe",
  )
}

///|
fn native_named_catalog_response(
  binding : @catalog.CatalogObservationBinding,
  resource_name : String,
  limits : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  response : @resource.NativeCredentialResponse,
) -> Result[@catalog.CatalogObservation, NativeSalesforceNamedCatalogIssue] {
  if response.status != 200 {
    return Err(MetadataReadUnavailable(response))
  }
  let sync = match @catalog.begin_named_catalog_sync([resource_name]) {
    Ok(value) => value
    Err(_) => return Err(InvalidCatalogConfiguration)
  }
  match
    @catalog.catalog_sync_describe(sync, resource_name, response.body, limits) {
    Ok(_) => ()
    Err(issue) => return Err(CatalogSyncFailure(issue, response))
  }
  match @catalog.finish_catalog_sync(sync) {
    Ok(_) => ()
    Err(issue) => return Err(CatalogSyncFailure(issue, response))
  }
  @catalog.prepare_catalog_observation(
    sync,
    binding,
    "",
    [Some(response.use_cid)],
    [Some(@catalog.catalog_response_sha256(response.body))],
    max_observation_bytes,
  ).map_err(issue => CatalogObservationFailure(issue, response))
}

///|
/// Describe one independently configured Provider Resource using the existing
/// credential service's exact grant, durable use claim and physical transport.
/// The returned Catalog is describe-only, never a complete inventory or write
/// permission. Retain its exact response/use with original Host custody before
/// restart; recover_named_catalog_observation restores without Provider I/O.
/// A failed/uncertain use is reconciled by that service, never automatically
/// repeated here. Provider metadata authority is separate from Effect approval.
pub fn observe_native_salesforce_named_catalog(
  service : @resource.NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : @resource.NativeCredentialScope,
  binding : @catalog.CatalogObservationBinding,
  credential_org_id : String,
  api_version : String,
  resource_name : String,
  limits : @catalog.DescribeLimits,
  max_observation_bytes : Int,
  current : () -> Bool,
) -> Result[
  (@catalog.CatalogObservation, @resource.NativeCredentialResponse),
  NativeSalesforceNamedCatalogIssue,
] {
  let path = match
    native_named_catalog_path(
      scope, binding, credential_org_id, api_version, resource_name,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    limits.max_fields < 1 ||
    limits.max_name_units < 1 ||
    max_observation_bytes < 1 {
    return Err(InvalidCatalogConfiguration)
  }
  if !current() {
    return Err(MetadataAccessDenied)
  }
  let response = match
    @resource.call_native_credential_resource_guarded_request_at_path(
      service,
      grant,
      use_id,
      scope,
      Get,
      path,
      Bytes::new(0),
      current,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CatalogCredential(issue))
  }
  // A read can have happened even if authority was revoked during transport.
  // Keep that response and its real use evidence, without issuing a Catalog.
  if !current() {
    return Err(MetadataAuthorizationChanged(response))
  }
  native_named_catalog_response(
    binding, resource_name, limits, max_observation_bytes, response,
  ).map(value => (value, response))
}
