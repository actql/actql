///|
/// One bounded in-process delivery, using the existing control loop's pacing.
/// Waiting preserves a busy-slot context request; Responding retains the
/// original Store response until a response- and CAS-bound ACK is received.
/// This is not a durable request/response ledger or restart proof.
priv enum PendingBundleCustody {
  Waiting(@remote.RemotePollBundleCustody)
  Responding(@agent.NativeBundleCustodyPendingReport)
}

///|
fn bundle_custody_configuration(
  matches : @argparse.Matches,
  delegation : @resident.ResidentSiteDelegation,
  generation : Int,
) -> @agent.NativeBundleCustodyConfiguration? raise CommandStop {
  match
    (
      optional(matches, "bundle-custody-workspace"),
      optional(matches, "bundle-custody-authority-scope-cid"),
      optional(matches, "bundle-custody-environment"),
    ) {
    (None, None, None) => None
    (Some(workspace_id), Some(authority_scope_cid), Some(environment)) =>
      Some({
        coordinator_authority: delegation.coordinator_authority,
        workspace_id,
        authority_scope_cid,
        environment,
        site_key: delegation.site_key,
        site_generation: generation,
        runtime_bundle_cid: delegation.runtime_bundle_cid,
        connector_registration: delegation.connector_registration,
        connector_revision: delegation.connector_revision,
        strategy_revision: delegation.strategy_revision,
      })
    _ => stop("incomplete Bundle custody scope configuration")
  }
}

///|
/// Called only while the existing exclusive executor slot is held and no
/// holder or stopped-holder recovery owns the Store. No Run is created.
fn control_bundle_custody_response(
  matches : @argparse.Matches,
  environment : ControlEnvironment,
  delivery : @remote.RemotePollBundleCustody,
  configuration : @agent.NativeBundleCustodyConfiguration,
) -> Result[@bundle_protocol.RemoteBundleCustodyResponse, String] raise CommandStop {
  let request = @remote.remote_poll_bundle_custody_request(delivery)
  // Refuse before opening the Store. The same current check is repeated at
  // the Store boundary, after configuration/signature setup.
  match
    @agent.native_bundle_custody_authorized(
      configuration,
      required(matches, "coordinator-authority"),
      request,
      !@slot.native_termination_requested(),
    ) {
    Err(_) => return Err("authority-or-admission")
    Ok(_) => ()
  }
  let signature_library = match
    @signature.load_library(required(matches, "crypto-library")) {
    Ok(value) => value
    Err(_) => return Err("signature-library")
  }
  let public_key = load_text(
    required(matches, "bundle-public-key-root"),
    required(matches, "bundle-public-key-file"),
    required_int64(matches, "max-file-bytes"),
  )
  let bundles = match
    @bundle.open_runtime_bundle_store(
      environment.sqlite_library,
      signature_library,
      required(matches, "runtime-root"),
      [
        {
          issuer_authority: required(matches, "bundle-issuer"),
          key_id: required(matches, "bundle-key-id"),
          public_key_pem: public_key,
        },
      ],
      required(matches, "target-triple"),
      environment.max_bytes,
      64,
      1024,
      environment.max_record_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err("store-open")
  }
  let result = @agent.prepare_native_bundle_custody_response(
    bundles,
    delivery,
    configuration,
    required(matches, "coordinator-authority"),
    !@slot.native_termination_requested(),
  )
  // No response escapes if Store cleanup is unconfirmed. Process termination
  // leaves durable custody in the original catalog for operator recovery.
  if !(bundles.close() is Ok(true)) {
    stop("Bundle custody Store close unconfirmed")
  }
  match result {
    Ok(response) => Ok(response)
    Err(@agent.AuthorityRejected) => Err("authority")
    Err(@agent.AdmissionClosed) => Err("admission-closed")
    Err(@agent.RegistrationMismatch) => Err("registration")
    Err(@agent.Store(_)) => Err("store")
  }
}
