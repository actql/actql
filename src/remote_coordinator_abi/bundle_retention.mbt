///|
/// Portable client bridge for the shared bundle custody value owner. Constructing
/// or admitting these values never authorizes a hold or mutates a physical Store.
#export_name("coordinatorBundleDistributionPrepare")
pub fn coordinator_bundle_distribution_prepare(
  members : Array[String],
) -> Result[@bundle.RemoteBundleDistribution, @bundle.RemoteBundleIssue] {
  @bundle.prepare_bundle_distribution(members)
}

///|
#export_name("coordinatorBundleDistributionIdentity")
pub fn coordinator_bundle_distribution_identity(
  value : @bundle.RemoteBundleDistribution,
) -> String {
  @bundle.bundle_distribution_identity(value)
}

///|
#export_name("coordinatorBundleDistributionJson")
pub fn coordinator_bundle_distribution_json(
  value : @bundle.RemoteBundleDistribution,
) -> Result[String, @bundle.RemoteBundleIssue] {
  @bundle.bundle_distribution_json(value)
}

///|
#export_name("coordinatorBundleDistributionProjection")
pub fn coordinator_bundle_distribution_projection(
  value : @bundle.RemoteBundleDistribution,
) -> Array[String] {
  @bundle.bundle_distribution_projection(value)
}

///|
#export_name("coordinatorBundleDistributionContains")
pub fn coordinator_bundle_distribution_contains(
  value : @bundle.RemoteBundleDistribution,
  runtime_bundle_cid : String,
) -> Bool {
  @bundle.bundle_distribution_contains(value, runtime_bundle_cid)
}

///|
#export_name("coordinatorBundleDistributionAdmitJson")
pub fn coordinator_bundle_distribution_admit_json(
  body : String,
  claimed_cid : String,
) -> Result[@bundle.RemoteBundleDistribution, @bundle.RemoteBundleIssue] {
  @bundle.admit_bundle_distribution_json(body, claimed_cid)
}

///|
#export_name("coordinatorBundleHoldScopePrepare")
pub fn coordinator_bundle_hold_scope_prepare(
  distribution : @bundle.RemoteBundleDistribution,
  coordinator_authority : String,
  workspace_id : String,
  authority_scope_cid : String,
  environment : String,
  set_revision_cid : String,
  runtime_bundle_cid : String,
  site_key : String,
  site_generation : Int,
  attempt_id : String,
) -> Result[@bundle.RemoteBundleHoldScope, @bundle.RemoteBundleIssue] {
  @bundle.prepare_bundle_hold_scope(
    distribution, coordinator_authority, workspace_id, authority_scope_cid, environment,
    set_revision_cid, runtime_bundle_cid, site_key, site_generation, attempt_id,
  )
}

///|
#export_name("coordinatorBundleHoldScopeIdentity")
pub fn coordinator_bundle_hold_scope_identity(
  value : @bundle.RemoteBundleHoldScope,
) -> String {
  @bundle.bundle_hold_scope_identity(value)
}

///|
#export_name("coordinatorBundleHoldScopeJson")
pub fn coordinator_bundle_hold_scope_json(
  value : @bundle.RemoteBundleHoldScope,
) -> Result[String, @bundle.RemoteBundleIssue] {
  @bundle.bundle_hold_scope_json(value)
}

///|
#export_name("coordinatorBundleHoldScopeProjection")
pub fn coordinator_bundle_hold_scope_projection(
  value : @bundle.RemoteBundleHoldScope,
) -> Array[String] {
  @bundle.bundle_hold_scope_projection(value)
}

///|
#export_name("coordinatorBundleHoldScopeAdmitJson")
pub fn coordinator_bundle_hold_scope_admit_json(
  distribution : @bundle.RemoteBundleDistribution,
  body : String,
  claimed_cid : String,
) -> Result[@bundle.RemoteBundleHoldScope, @bundle.RemoteBundleIssue] {
  @bundle.admit_bundle_hold_scope_json(distribution, body, claimed_cid)
}

///|
#export_name("coordinatorBundleHoldBindingIdentity")
pub fn coordinator_bundle_hold_binding_identity(
  value : @bundle.RemoteBundleHoldBinding,
) -> String {
  @bundle.bundle_hold_binding_identity(value)
}

///|
#export_name("coordinatorBundleHoldBindingJson")
pub fn coordinator_bundle_hold_binding_json(
  value : @bundle.RemoteBundleHoldBinding,
) -> Result[String, @bundle.RemoteBundleIssue] {
  @bundle.bundle_hold_binding_json(value)
}

///|
#export_name("coordinatorBundleHoldBindingProjection")
pub fn coordinator_bundle_hold_binding_projection(
  value : @bundle.RemoteBundleHoldBinding,
) -> Array[String] {
  @bundle.bundle_hold_binding_projection(value)
}

///|
#export_name("coordinatorBundleHoldBindingScope")
pub fn coordinator_bundle_hold_binding_scope(
  value : @bundle.RemoteBundleHoldBinding,
) -> Result[@bundle.RemoteBundleHoldScope, @bundle.RemoteBundleIssue] {
  @bundle.bundle_hold_binding_scope(value)
}

///|
#export_name("coordinatorBundleHoldBindingAdmitJson")
pub fn coordinator_bundle_hold_binding_admit_json(
  distribution : @bundle.RemoteBundleDistribution,
  body : String,
  claimed_cid : String,
) -> Result[@bundle.RemoteBundleHoldBinding, @bundle.RemoteBundleIssue] {
  @bundle.admit_bundle_hold_binding_json(distribution, body, claimed_cid)
}

///|
#export_name("coordinatorBundleCustodyContextQueryPrepare")
pub fn coordinator_bundle_custody_context_query_prepare(
  distribution : @bundle.RemoteBundleDistribution,
  scope : @bundle.RemoteBundleHoldScope,
) -> Result[@bundle.RemoteBundleCustodyRequest, @bundle.RemoteBundleIssue] {
  @bundle.prepare_bundle_custody_context_query(distribution, scope)
}

///|
#export_name("coordinatorBundleCustodyRequestPrepare")
pub fn coordinator_bundle_custody_request_prepare(
  distribution : @bundle.RemoteBundleDistribution,
  binding : @bundle.RemoteBundleHoldBinding,
  operation : String,
) -> Result[@bundle.RemoteBundleCustodyRequest, @bundle.RemoteBundleIssue] {
  @bundle.prepare_bundle_custody_request(distribution, binding, operation)
}

///|
#export_name("coordinatorBundleCustodyRequestIdentity")
pub fn coordinator_bundle_custody_request_identity(
  value : @bundle.RemoteBundleCustodyRequest,
) -> String {
  @bundle.bundle_custody_request_identity(value)
}

///|
#export_name("coordinatorBundleCustodyRequestJson")
pub fn coordinator_bundle_custody_request_json(
  value : @bundle.RemoteBundleCustodyRequest,
) -> Result[String, @bundle.RemoteBundleIssue] {
  @bundle.bundle_custody_request_json(value)
}

///|
#export_name("coordinatorBundleCustodyRequestOperation")
pub fn coordinator_bundle_custody_request_operation(
  value : @bundle.RemoteBundleCustodyRequest,
) -> String {
  @bundle.bundle_custody_request_operation(value)
}

///|
#export_name("coordinatorBundleCustodyRequestScope")
pub fn coordinator_bundle_custody_request_scope(
  value : @bundle.RemoteBundleCustodyRequest,
) -> @bundle.RemoteBundleHoldScope {
  @bundle.bundle_custody_request_scope(value)
}

///|
/// Project optional handles without depending on the JS Option representation.
#export_name("coordinatorBundleCustodyRequestBindings")
pub fn coordinator_bundle_custody_request_bindings(
  value : @bundle.RemoteBundleCustodyRequest,
) -> Array[@bundle.RemoteBundleHoldBinding] {
  match @bundle.bundle_custody_request_binding(value) {
    Some(binding) => [binding]
    None => []
  }
}

///|
#export_name("coordinatorBundleCustodyRequestAdmitJson")
pub fn coordinator_bundle_custody_request_admit_json(
  body : String,
  claimed_cid : String,
) -> Result[@bundle.RemoteBundleCustodyRequest, @bundle.RemoteBundleIssue] {
  @bundle.admit_bundle_custody_request_json(body, claimed_cid)
}

///|
#export_name("coordinatorBundleCustodyResponseAdmitJson")
pub fn coordinator_bundle_custody_response_admit_json(
  request : @bundle.RemoteBundleCustodyRequest,
  body : String,
  claimed_cid : String,
) -> Result[@bundle.RemoteBundleCustodyResponse, @bundle.RemoteBundleIssue] {
  @bundle.admit_bundle_custody_response_json(request, body, claimed_cid)
}

///|
#export_name("coordinatorBundleCustodyResponseIdentity")
pub fn coordinator_bundle_custody_response_identity(
  value : @bundle.RemoteBundleCustodyResponse,
) -> String {
  @bundle.bundle_custody_response_identity(value)
}

///|
#export_name("coordinatorBundleCustodyResponseJson")
pub fn coordinator_bundle_custody_response_json(
  value : @bundle.RemoteBundleCustodyResponse,
) -> Result[String, @bundle.RemoteBundleIssue] {
  @bundle.bundle_custody_response_json(value)
}

///|
#export_name("coordinatorBundleCustodyResponseKind")
pub fn coordinator_bundle_custody_response_kind(
  value : @bundle.RemoteBundleCustodyResponse,
) -> String {
  @bundle.bundle_custody_response_kind(value)
}

///|
#export_name("coordinatorBundleCustodyResponseBinding")
pub fn coordinator_bundle_custody_response_binding(
  value : @bundle.RemoteBundleCustodyResponse,
) -> @bundle.RemoteBundleHoldBinding {
  @bundle.bundle_custody_response_binding(value)
}

///|
#export_name("coordinatorBundleCustodyResponseObservationText")
pub fn coordinator_bundle_custody_response_observation_text(
  value : @bundle.RemoteBundleCustodyResponse,
) -> String {
  @bundle.bundle_custody_response_observation_text(value)
}

///|
#export_name("coordinatorBundleCustodyResponseCatalogText")
pub fn coordinator_bundle_custody_response_catalog_text(
  value : @bundle.RemoteBundleCustodyResponse,
) -> String {
  @bundle.bundle_custody_response_catalog_incarnation_text(value)
}

///|
#export_name("coordinatorBundleCustodyResponseRevisionText")
pub fn coordinator_bundle_custody_response_revision_text(
  value : @bundle.RemoteBundleCustodyResponse,
) -> String {
  @bundle.bundle_custody_response_record_revision_text(value)
}
