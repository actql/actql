///|
/// Verified context from this Store's existing catalog and physical member.
pub(all) struct NativeRuntimeBundleRetentionContext {
  catalog_incarnation : String
  runtime_bundle_cid : String
  initial_revision : Int
  manifest : @bundle.RemoteBundleManifest
}

///|
/// Observation of the original binding, never authority to replace its attempt.
pub(all) struct NativeRuntimeBundleHoldReceipt {
  binding_cid : String
  runtime_bundle_cid : String
  observation : @bundle.RemoteBundleHoldObservation
  catalog_incarnation : String?
  record_revision : Int?
}

///|
/// Storage adapter only. The authenticated Site receiver must authorize the
/// coordinator, workspace scope, registration and admission before calling it.
/// Replaying a context query observes current context; it is not an immutable
/// response journal. Persist its response before handing out any retain request.
pub fn NativeRuntimeBundleStore::custody(
  self : NativeRuntimeBundleStore,
  request : @bundle.RemoteBundleCustodyRequest,
) -> Result[@bundle.RemoteBundleCustodyResponse, NativeRuntimeBundleStoreIssue] {
  match @bundle.bundle_custody_request_json(request) {
    Ok(_) => ()
    Err(issue) => return Err(Bundle(issue))
  }
  match @bundle.bundle_custody_request_binding(request) {
    None => {
      let scope = @bundle.bundle_custody_request_scope(request)
      let parts = @bundle.bundle_hold_scope_projection(scope)
      let context = match self.retention_context(parts[7]) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let binding = match
        @bundle.prepare_bundle_hold_binding_from_scope(
          scope,
          context.catalog_incarnation,
          context.initial_revision,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Bundle(issue))
      }
      match @bundle.prepare_bundle_custody_context_response(request, binding) {
        Ok(value) => Ok(value)
        Err(issue) => Err(Bundle(issue))
      }
    }
    Some(binding) => {
      let receipt = match @bundle.bundle_custody_request_operation(request) {
        "retain" => self.retain_member(binding)
        "release" => self.release_member(binding)
        "query" => self.inspect_member_hold(binding)
        _ => return Err(InvalidConfiguration)
      }
      let receipt = match receipt {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        @bundle.prepare_bundle_custody_response(
          request,
          receipt.observation,
          receipt.catalog_incarnation,
          receipt.record_revision,
        ) {
        Ok(value) => Ok(value)
        Err(issue) => Err(Bundle(issue))
      }
    }
  }
}
