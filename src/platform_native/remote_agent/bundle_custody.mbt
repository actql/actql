///|
/// Explicit trusted installation scope. This is not decoded from a poll body,
/// and absence of a configured scope admits no Bundle custody operations.
/// Existing transport authentication identifies the configured Coordinator.
pub(all) struct NativeBundleCustodyConfiguration {
  coordinator_authority : String
  workspace_id : String
  authority_scope_cid : String
  environment : String
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  strategy_revision : String
}

///|
pub(all) enum NativeBundleCustodyIssue {
  AuthorityRejected
  AdmissionClosed
  RegistrationMismatch
  Store(@bundle_store.NativeRuntimeBundleStoreIssue)
}

///|
/// Check current trusted configuration immediately before the Store call,
/// including after waiting for an existing executor slot. An earlier poll is
/// not an authority grant and cannot bypass a later admission closure.
pub fn native_bundle_custody_authorized(
  configuration : NativeBundleCustodyConfiguration,
  authenticated_coordinator : String,
  request : @bundle_protocol.RemoteBundleCustodyRequest,
  admission_open : Bool,
) -> Result[Unit, NativeBundleCustodyIssue] {
  let scope = @bundle_protocol.bundle_hold_scope_projection(
    @bundle_protocol.bundle_custody_request_scope(request),
  )
  if configuration.coordinator_authority.is_empty() ||
    configuration.workspace_id.is_empty() ||
    configuration.authority_scope_cid.is_empty() ||
    configuration.environment.is_empty() ||
    configuration.site_key.is_empty() ||
    configuration.site_generation < 0 ||
    configuration.runtime_bundle_cid.is_empty() ||
    configuration.connector_registration.is_empty() ||
    configuration.connector_revision.is_empty() ||
    configuration.strategy_revision.is_empty() ||
    authenticated_coordinator != configuration.coordinator_authority ||
    scope[1] != authenticated_coordinator ||
    scope[2] != configuration.workspace_id ||
    scope[3] != configuration.authority_scope_cid ||
    scope[4] != configuration.environment ||
    scope[7] != configuration.runtime_bundle_cid ||
    scope[8] != configuration.site_key ||
    scope[9] != configuration.site_generation.to_string() {
    return Err(AuthorityRejected)
  }
  if @bundle_protocol.bundle_custody_request_operation(request) == "retain" &&
    !admission_open {
    return Err(AdmissionClosed)
  }
  Ok(())
}

///|
/// No runtime, dispatch journal or Run admission participates in this path.
/// The existing Bundle Store is the sole physical custodian and supplies the
/// typed response from its real catalog and hold transition.
pub fn prepare_native_bundle_custody_response(
  store : @bundle_store.NativeRuntimeBundleStore,
  delivery : @remote.RemotePollBundleCustody,
  configuration : NativeBundleCustodyConfiguration,
  authenticated_coordinator : String,
  admission_open : Bool,
) -> Result[
  @bundle_protocol.RemoteBundleCustodyResponse,
  NativeBundleCustodyIssue,
] {
  let request = @remote.remote_poll_bundle_custody_request(delivery)
  match
    native_bundle_custody_authorized(
      configuration, authenticated_coordinator, request, admission_open,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match store.inspect(configuration.runtime_bundle_cid) {
    Ok(Some(snapshot)) => {
      let manifest = match
        @bundle_protocol.admit_bundle_manifest_json(
          snapshot.manifest_json,
          configuration.runtime_bundle_cid,
        ) {
        Ok(value) => value
        Err(_) => return Err(RegistrationMismatch)
      }
      let registration = @bundle_protocol.bundle_manifest_projection(manifest)
      if registration[7] != configuration.connector_registration ||
        registration[8] != configuration.connector_revision ||
        registration[9] != configuration.strategy_revision {
        return Err(RegistrationMismatch)
      }
    }
    // Missing content is reported by the real Store, never promoted here to
    // an absence fence, success, or permission to recreate a runtime.
    Ok(None) => ()
    Err(issue) => return Err(Store(issue))
  }
  match store.custody(request) {
    Ok(response) => Ok(response)
    Err(issue) => Err(Store(issue))
  }
}

///|
/// A single bounded process-local transport obligation. Only the original
/// response is retained; this creates no durable Store or Set state.
struct NativeBundleCustodyPendingReport {
  delivery : @remote.RemotePollBundleCustody
  response : @bundle_protocol.RemoteBundleCustodyResponse
}

///|
pub fn prepare_native_bundle_custody_pending_report(
  delivery : @remote.RemotePollBundleCustody,
  response : @bundle_protocol.RemoteBundleCustodyResponse,
) -> Result[NativeBundleCustodyPendingReport, @remote.DispatchIssue] {
  match
    @remote.remote_bundle_custody_observation_json(
      @remote.remote_poll_bundle_custody_request(delivery),
      response,
      @remote.remote_poll_bundle_custody_delivery_revision(delivery),
    ) {
    Ok(_) => Ok({ delivery, response, })
    Err(issue) => Err(issue)
  }
}

///|
/// One existing-loop send, never a Store retry. A transport failure retains
/// the same obligation; a checked ACK or obsolete disposition retires only
/// that obligation. The callback is the authenticated client reply boundary.
pub fn advance_native_bundle_custody_report(
  pending : NativeBundleCustodyPendingReport?,
  post : (
    @remote.RemotePollBundleCustody,
    @bundle_protocol.RemoteBundleCustodyResponse,
  ) -> Result[
    @remote.RemoteBundleCustodyObservationReply,
    @client.NativeRemoteClientIssue,
  ],
) -> (
  NativeBundleCustodyPendingReport?,
  @remote.RemoteBundleCustodyObservationReply?,
) {
  match pending {
    None => (None, None)
    Some(original) =>
      match post(original.delivery, original.response) {
        Ok(reply) => (None, Some(reply))
        Err(_) => (Some(original), None)
      }
  }
}
