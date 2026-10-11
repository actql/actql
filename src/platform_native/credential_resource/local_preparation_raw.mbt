///|
/// Existing Store/crypto Owners bound by trusted Host assembly. This material
/// grants neither credential use nor read authority and creates no send slot.
struct NativeLocalPreparationRawStore {
  store : @publication.Store
  crypto : @signature.Library
  key : Bytes
}

///|
pub fn bind_native_local_preparation_raw_store(
  store : @publication.Store,
  crypto : @signature.Library,
  key : Bytes,
) -> Result[NativeLocalPreparationRawStore, NativeCredentialResourceIssue] {
  if key.length() != 32 {
    return Err(InvalidConfiguration)
  }
  Ok({ store, crypto, key: key[:].to_owned(), })
}

///|
fn prepare_original_raw_custody(
  service : NativeCredentialResourceService,
  grant : NativeOwnedCredentialGrant,
  credential_use : NativeOwnedCredentialUse,
) -> Result[
  @publication.LocalPreparationRawCustody?,
  NativeCredentialResourceIssue,
] {
  match (grant, credential_use) {
    (PreparationGrant(original_grant), PreparationUse(original_use)) => {
      guard service.preparation_raw_store is Some(raw) else {
        return Err(InvalidConfiguration)
      }
      raw.store
      .prepare_local_preparation_raw_observation(
        original_grant,
        original_use,
        service.client,
        raw.crypto,
        raw.key,
      )
      .map(value => Some(value))
      .map_err(issue => RawObservation(issue))
    }
    (RemoteGrant(_), RemoteUse(_)) | (LocalGrant(_), LocalUse(_)) => Ok(None)
    _ => Err(Credential(@credential.CredentialUseCollision))
  }
}

///|
fn authorize_original_raw_access(
  service : NativeCredentialResourceService,
  grant : NativeOwnedCredentialGrant,
  credential_use : NativeOwnedCredentialUse,
  scope : NativeOwnedCredentialScope,
  current : (() -> Bool)?,
  stage : String,
) -> Result[Unit, NativeCredentialResourceIssue] {
  guard (grant, credential_use, scope)
    is (PreparationGrant(_), PreparationUse(_), PreparationScope(_)) &&
    owned_operation_for(service, scope) is Some(operation) else {
    return Err(AccessDenied)
  }
  let grant_cid = owned_credential_grant_cid(grant)
  let allowed = authorize_owned_credential(service, scope, {
    stage,
    grant_cid,
    use_cid: Some(owned_credential_use_cid(credential_use)),
    request: Some({ verb: @http.Get, path: operation.path, body: b"", }),
  })
  let current_time = match observe_trusted_clock(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fence = match current {
    Some(check) => check()
    None => false
  }
  // Read revocation after every Host/clock/fence callback. Current read/fence
  // failure cannot release or replace the saved original cleanup custody.
  let revoked = match native_credential_grant_revoked(service, grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !allowed || !fence {
    return Err(AccessDenied)
  }
  authorize_owned_credential_use(credential_use, current_time, revoked, scope).map_err(issue => {
      Credential(issue)
    },
  )
}

///|
fn authorize_original_raw_return(
  service : NativeCredentialResourceService,
  grant : NativeOwnedCredentialGrant,
  credential_use : NativeOwnedCredentialUse,
  scope : NativeOwnedCredentialScope,
  current : (() -> Bool)?,
) -> Result[Unit, NativeCredentialResourceIssue] {
  authorize_original_raw_access(
    service, grant, credential_use, scope, current, "raw-return",
  )
}

///|
/// The original journal outcome and raw transport observation are distinct.
/// A retained response with an unknown/claimed outcome is not semantic success.
pub struct NativeLocalPreparationRawRecovery {
  original_use : NativeCredentialUseStatus
  observation : @publication.NativeLocalPreparationRawObservation
}

///|
/// Restore only the original admitted use and retained response. No claim,
/// ordinal, terminal repair, new reservation, HTTP entry or Catalog admission.
pub fn query_native_local_preparation_raw_observation(
  service : NativeCredentialResourceService,
  grant : @credential.LocalPreparationCredentialGrant,
  use_id : String,
  scope : @credential.LocalPreparationCredentialScope,
  current : () -> Bool,
) -> Result[NativeLocalPreparationRawRecovery, NativeCredentialResourceIssue] {
  let original_grant = PreparationGrant(grant)
  let original_scope = PreparationScope(scope)
  let status = match
    query_native_owned_credential_use(
      service, original_grant, use_id, original_scope,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original_use = match
    read_owned_credential_use(service, original_grant, use_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if owned_credential_use_cid(original_use) != status.use_cid {
    return Err(Journal(@sqlite.Collision))
  }
  match
    authorize_original_raw_access(
      service,
      original_grant,
      original_use,
      original_scope,
      Some(current),
      "raw-query",
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard (service.preparation_raw_store, original_use)
    is (Some(raw), PreparationUse(admitted_use)) else {
    return Err(InvalidConfiguration)
  }
  let custody = match
    raw.store.restore_local_preparation_raw_observation(
      grant,
      admitted_use,
      raw.crypto,
      raw.key,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RawObservation(issue))
  }
  let observation = match custody.confirm() {
    Ok(value) => value
    Err(issue) => return Err(RawObservation(issue))
  }
  if observation.use_cid != status.use_cid ||
    (status.status is Some(saved) && saved != observation.status) {
    return Err(Journal(@sqlite.Collision))
  }
  match
    authorize_original_raw_return(
      service,
      original_grant,
      original_use,
      original_scope,
      Some(current),
    ) {
    Ok(_) => Ok({ original_use: status, observation, })
    Err(issue) => Err(issue)
  }
}
