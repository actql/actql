///|
// This is request matching only, never an operational authorization. The
// opaque acknowledgement below separately checks live Work and current Owner
// authority. Credential use identity/lifetime/revocation remain with its Owner.
fn local_preparation_credential_request_matches(
  grant : @credential.LocalPreparationCredentialGrant,
  authorization : @credential_resource.NativeLocalPreparationCredentialAuthorization,
) -> Bool {
  let scope = @credential.local_preparation_credential_grant_scope(grant)
  if authorization.grant_cid !=
    @credential.local_preparation_credential_grant_cid(grant) ||
    authorization.scope != scope {
    return false
  }
  // This live preparation acknowledgement is not a post-closure lookup or
  // response disclosure permit. Those use their own current read authority.
  match (authorization.stage, authorization.use_cid) {
    ("claim", None) => ()
    ("send", Some(cid)) if !cid.is_empty() => ()
    _ => return false
  }
  guard authorization.request is Some(request) else { return false }
  request.verb is @http.Get &&
  request.path == scope.request_path &&
  request.body.length() == 0 &&
  scope.request_method == "GET" &&
  scope.operation == "salesforce:record:observe"
}

///|
/// Bridge the existing credential Owner's claim/send callback to an actual
/// immutable grant adoption acknowledgement. Public CIDs, caller booleans and
/// restored identity-only references cannot construct this acknowledgement.
/// Recheck the original Work, selected installation, Account read and issuer
/// authority, and committed packet/reservation before and after matching.
/// This neither issues a grant nor proves a physical use or transport result.
pub fn NativeLocalPreparationGrantAcknowledgement::authorize_credential_request(
  self : NativeLocalPreparationGrantAcknowledgement,
  authorization : @credential_resource.NativeLocalPreparationCredentialAuthorization,
) -> Result[Unit, NativeLocalSalesforcePreparationIssue] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard self.operation.original.grant is PreparationGrant(grant) else {
    return Err(ForeignInstallation)
  }
  if !local_preparation_credential_request_matches(grant, authorization) {
    return Err(AuthorizationDenied)
  }
  self.require_current()
}

///|
/// Supply the existing credential service's typed claim/send hook directly
/// from this opaque original ACK. No cached authorization result or caller
/// allowance is captured. Every callback re-enters the same current checks.
/// Query/return need a separate current lookup/disclosure authorization; this
/// hook must not be used as a permissive fallback for those operations.
pub fn NativeLocalPreparationGrantAcknowledgement::credential_authorizer(
  self : NativeLocalPreparationGrantAcknowledgement,
) -> (@credential_resource.NativeLocalPreparationCredentialAuthorization) -> Bool {
  authorization => self.authorize_credential_request(authorization) is Ok(_)
}
