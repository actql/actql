///|
/// An explicit trusted Local Host installation over the same credential
/// resource service, database, clock and use/outcome custody. It supplies no
/// Remote authorization and cannot create a secret, grant or Run permission.
pub fn install_native_local_credential_resource_service(
  database : @sqlite.Database,
  client : @http.Client,
  operations : Array[NativeCredentialOperation],
  authorize : (NativeLocalCredentialAuthorization) -> Bool,
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  install_native_credential_resource_service_with_clock(
    database,
    client,
    operations,
    _ => false,
    () => @env.now().reinterpret_as_int64(),
    authorize_local=Some(authorize),
  )
}

///|
/// Local requires a current guard at its public send boundary. Trusted Host
/// assembly must check its original opaque execution claim and cancellation
/// fence in that guard; a Bool callback is not itself such a claim. The exact
/// isolated transport body must match the original typed Local grant.
pub fn call_native_local_credential_resource_guarded_request_at_path(
  service : NativeCredentialResourceService,
  grant : @credential.LocalCredentialGrant,
  use_id : String,
  scope : @credential.LocalCredentialScope,
  verb : @http.NativeHttpMethod,
  expected_path : String,
  body : Bytes,
  current : () -> Bool,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned_scope(
    service,
    LocalGrant(grant),
    use_id,
    LocalScope(scope),
    Some(expected_path),
    verb,
    body,
    Some(current),
  )
}

///|
/// Observe the saved original use through current query/return authorization.
/// This never claims another ordinal or invokes the Provider. A claimed or
/// unknown use is not inferred to be unsent or safe to retry.
pub fn query_native_local_credential_use(
  service : NativeCredentialResourceService,
  grant : @credential.LocalCredentialGrant,
  use_id : String,
  scope : @credential.LocalCredentialScope,
) -> Result[NativeCredentialUseStatus, NativeCredentialResourceIssue] {
  query_native_owned_credential_use(
    service,
    LocalGrant(grant),
    use_id,
    LocalScope(scope),
  )
}

///|
pub fn revoke_native_local_credential_grant(
  service : NativeCredentialResourceService,
  grant : @credential.LocalCredentialGrant,
) -> Result[Unit, NativeCredentialResourceIssue] {
  revoke_native_owned_credential_grant(
    service,
    @credential.local_credential_grant_cid(grant),
  )
}
