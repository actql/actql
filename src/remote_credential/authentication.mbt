///|
/// Private request correspondence, not an authentication grant, current-policy
/// observation or durable use claim. Material is the physical credential
/// supplier's original opaque custody, never a key ID or an equal-byte key.
struct CredentialAuthenticationRequest[Material] {
  parent : RemoteCredentialUse
  grant : RemoteCredentialGrant
  material : Material
  body_digest : String
  body_bytes : Int
  deadline_unix_ms : Int64
}

///|
/// The separately claimed authentication use and its original request. There
/// is no serialization or constructor that recreates this pair from DATA.
struct CredentialAuthenticationOperation[Material] {
  request : CredentialAuthenticationRequest[Material]
  credential_use : RemoteCredentialUse
}

///|
fn authentication_parent_scope_matches(
  parent : RemoteCredentialGrant,
  authentication : RemoteCredentialGrant,
) -> Bool {
  parent.issuer_authority == authentication.issuer_authority &&
  parent.principal == authentication.principal &&
  parent.namespace_id == authentication.namespace_id &&
  parent.environment == authentication.environment &&
  parent.site_key == authentication.site_key &&
  parent.site_generation == authentication.site_generation &&
  parent.runtime_bundle_cid == authentication.runtime_bundle_cid &&
  parent.connector_registration == authentication.connector_registration &&
  parent.connector_revision == authentication.connector_revision &&
  parent.run_invocation_cid == authentication.run_invocation_cid &&
  parent.task_attempt == authentication.task_attempt &&
  parent.dispatch_request_cid == authentication.dispatch_request_cid &&
  authentication.expires_unix_ms <= parent.expires_unix_ms
}

///|
fn authentication_request_shape(
  http_method : String,
  path : String,
  media_type : String,
) -> Bool {
  http_method == "POST" &&
  path == "/token" &&
  media_type == "application/x-www-form-urlencoded"
}

///|
/// Bind the registered Google authentication dependency to the original parent
/// use, separately issued grant and actual request bytes. The supplier must
/// independently admit Material's membership, subject/scopes/key generation
/// and current declaration; this pure function cannot issue that authority.
/// Check the byte ceiling before hashing. Neither secret bytes nor their hash
/// have a public projection, canonical identity or diagnostic representation.
pub fn[Material] prepare_credential_authentication_request(
  parent : RemoteCredentialUse,
  grant : RemoteCredentialGrant,
  material : Material,
  http_method : String,
  path : String,
  media_type : String,
  body : Bytes,
  max_body_bytes : Int,
  deadline_unix_ms : Int64,
) -> Result[CredentialAuthenticationRequest[Material], RemoteCredentialIssue] {
  if credential_use_json(parent) is Err(_) ||
    credential_grant_json(grant) is Err(_) ||
    !authentication_parent_scope_matches(parent.grant, grant) ||
    physical_equal(parent.grant, grant) ||
    parent.grant.resource_origin == grant.resource_origin ||
    parent.grant.operation == grant.operation {
    return Err(CredentialGrantIdentityMismatch)
  }
  if grant.resource_origin != "https://oauth2.googleapis.com" ||
    !authentication_request_shape(http_method, path, media_type) ||
    max_body_bytes <= 0 ||
    body.length() <= 0 ||
    body.length() > max_body_bytes ||
    deadline_unix_ms <= 0L ||
    deadline_unix_ms > grant.expires_unix_ms {
    return Err(InvalidCredentialGrant)
  }
  Ok({
    parent,
    grant,
    material,
    body_digest: @sha.hex(body),
    body_bytes: body.length(),
    deadline_unix_ms,
  })
}

///|
fn[Material] authentication_request_matches(
  request : CredentialAuthenticationRequest[Material],
  parent : RemoteCredentialUse,
  credential_use : RemoteCredentialUse,
  material : Material,
  http_method : String,
  path : String,
  media_type : String,
  body : Bytes,
  trusted_now_ms : Int64,
) -> Result[Unit, RemoteCredentialIssue] {
  if !physical_equal(request.parent, parent) ||
    !physical_equal(request.grant, credential_use.grant) ||
    !physical_equal(request.material, material) ||
    !authentication_request_shape(http_method, path, media_type) ||
    body.length() != request.body_bytes {
    return Err(CredentialGrantIdentityMismatch)
  }
  if trusted_now_ms < 0L || trusted_now_ms >= request.deadline_unix_ms {
    return Err(CredentialGrantInactive)
  }
  if credential_use_json(credential_use) is Err(_) ||
    @sha.hex(body) != request.body_digest {
    return Err(CredentialGrantIdentityMismatch)
  }
  Ok(())
}

///|
/// Called with the original authentication use after its existing journal
/// claim. This checks correspondence only; it neither claims that journal nor
/// replaces its signature/current authorization, ordinal or Unknown fence.
pub fn[Material] bind_credential_authentication_use(
  request : CredentialAuthenticationRequest[Material],
  parent : RemoteCredentialUse,
  credential_use : RemoteCredentialUse,
  material : Material,
  http_method : String,
  path : String,
  media_type : String,
  body : Bytes,
  trusted_now_ms : Int64,
) -> Result[CredentialAuthenticationOperation[Material], RemoteCredentialIssue] {
  match
    authentication_request_matches(
      request, parent, credential_use, material, http_method, path, media_type, body,
      trusted_now_ms,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => Ok({ request, credential_use, })
  }
}

///|
/// Recheck the same original pair at the existing physical boundary and after
/// awaits. The caller still checks its real current authority and resource
/// custody; a matching pair is not a send or cleanup permission.
pub fn[Material] check_credential_authentication_operation(
  operation : CredentialAuthenticationOperation[Material],
  request : CredentialAuthenticationRequest[Material],
  parent : RemoteCredentialUse,
  credential_use : RemoteCredentialUse,
  material : Material,
  http_method : String,
  path : String,
  media_type : String,
  body : Bytes,
  trusted_now_ms : Int64,
) -> Result[Unit, RemoteCredentialIssue] {
  if !physical_equal(operation.request, request) ||
    !physical_equal(operation.credential_use, credential_use) {
    return Err(CredentialGrantIdentityMismatch)
  }
  authentication_request_matches(
    request, parent, credential_use, material, http_method, path, media_type, body,
    trusted_now_ms,
  )
}
