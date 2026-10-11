///|
fn catalog_use_matches_dispatch(
  request : @remote.DispatchRequest,
  grant : @credential.RemoteCredentialGrant,
  credential_use : @credential.RemoteCredentialUse,
) -> Bool {
  let fields = @credential.credential_grant_projection(grant)
  let execution = @remote.dispatch_request_execution_scope(request)
  let route = @remote.dispatch_request_journal_key(request)
  let use_fields = @credential.credential_use_projection(credential_use)
  fields.length() == 17 &&
  execution.length() >= 3 &&
  route.length() == 7 &&
  use_fields.length() == 4 &&
  use_fields[1] == fields[0] &&
  fields[5] == execution[0] &&
  fields[6] == execution[1] &&
  fields[7] == execution[2] &&
  fields[11] == "salesforce:catalog:describe" &&
  fields[13] == route[6] &&
  fields[14] == @remote.dispatch_request_identity(request)
}
