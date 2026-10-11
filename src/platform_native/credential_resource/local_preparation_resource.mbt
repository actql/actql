///|
/// The existing private-root Owner issued this original installation material.
/// The operation's legacy secret_path is not used by Local Preparation; the
/// physical hook opens only the retained projection below its original root.
pub(all) struct NativeLocalPreparationCredentialInstallation {
  operation : NativeCredentialOperation
  file : @filesystem.PrivateFileProjection
}

///|
/// Install only the finite read-only preparation alternative on the existing
/// credential database, trusted clock, use claim and transport Owner. Remote
/// and Local mutation authorization are not borrowed from this callback.
pub fn install_native_local_preparation_credential_resource_service(
  database : @sqlite.Database,
  client : @http.Client,
  installations : Array[NativeLocalPreparationCredentialInstallation],
  authorize : (NativeLocalPreparationCredentialAuthorization) -> Bool,
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  let operations = installations.map(value => value.operation)
  if operations.any(operation => {
      operation.operation != "salesforce:record:observe" ||
      operation.verb != @http.Get ||
      operation.max_request_bytes != 0
    }) {
    return Err(InvalidConfiguration)
  }
  install_native_credential_resource_service_with_clock(
    database,
    client,
    operations,
    _ => false,
    () => @env.now().reinterpret_as_int64(),
    authorize_preparation=Some(authorize),
    preparation_installations=installations,
  )
}

///|
fn preparation_installation_for(
  service : NativeCredentialResourceService,
  scope : NativeOwnedCredentialScope,
) -> @filesystem.PrivateFileProjection? {
  guard scope is PreparationScope(original) else { return None }
  let mut found = None
  for installation in service.preparation_installations {
    if installation.operation.resource_origin == original.resource_origin &&
      installation.operation.operation == original.operation {
      if found is Some(_) {
        return None
      }
      found = Some(installation.file)
    }
  }
  found
}

///|
/// Trusted Host assembly must retain the original opaque Work fence, checked
/// GET request and acknowledged grant, independently check current read and
/// issuer authority, and recheck cancellation after callbacks. A public fence
/// CID or this callback alone cannot provide those operational facts.
pub fn call_native_local_preparation_credential_resource_guarded_request_at_path(
  service : NativeCredentialResourceService,
  grant : @credential.LocalPreparationCredentialGrant,
  use_id : String,
  scope : @credential.LocalPreparationCredentialScope,
  expected_path : String,
  current : () -> Bool,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned_scope(
    service,
    PreparationGrant(grant),
    use_id,
    PreparationScope(scope),
    Some(expected_path),
    @http.Get,
    b"",
    Some(current),
  )
}

///|
/// Query only the saved original use. Claimed/unknown is not evidence that an
/// observation was unsent, and lookup never claims another ordinal or sends.
pub fn query_native_local_preparation_credential_use(
  service : NativeCredentialResourceService,
  grant : @credential.LocalPreparationCredentialGrant,
  use_id : String,
  scope : @credential.LocalPreparationCredentialScope,
) -> Result[NativeCredentialUseStatus, NativeCredentialResourceIssue] {
  query_native_owned_credential_use(
    service,
    PreparationGrant(grant),
    use_id,
    PreparationScope(scope),
  )
}

///|
pub fn revoke_native_local_preparation_credential_grant(
  service : NativeCredentialResourceService,
  grant : @credential.LocalPreparationCredentialGrant,
) -> Result[Unit, NativeCredentialResourceIssue] {
  revoke_native_owned_credential_grant(
    service,
    @credential.local_preparation_credential_grant_cid(grant),
  )
}
