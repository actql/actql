///|
/// Direct Local uses the real adopted Host and checked operation. These are
/// original bindings, not a Site, DispatchRequest or permission callback.
/// Admission of this value alone never supplies current authority or a secret.
pub(all) struct LocalCredentialScope {
  account_configuration_cid : String
  account_id : String
  attempt_id : String
  authority_scope_cid : String
  connector_registration : String
  connector_revision : String
  fence_claimant : String
  fence_generation : Int64
  fence_intent_cid : String
  host_adoption_cid : String
  operation : String
  operation_occurrence_cid : String
  principal : String
  request_body_cid : String
  request_cid : String
  request_method : String
  request_path : String
  resource_origin : String
  run_invocation_cid : String
  submission_scope_cid : String
  unit_definition_cid : String
} derive(Eq, Debug)

///|
struct LocalCredentialGrant {
  issuer_authority : String
  scope : LocalCredentialScope
  expires_unix_ms : Int64
  max_uses : Int
  grant_cid : String
}

///|
struct LocalCredentialUse {
  grant : LocalCredentialGrant
  use_id : String
  use_ordinal : Int
  use_cid : String
}

///|
fn valid_local_credential_scope(scope : LocalCredentialScope) -> Bool {
  valid_cid(scope.account_configuration_cid) &&
  valid_cid(scope.authority_scope_cid) &&
  valid_cid(scope.fence_intent_cid) &&
  bounded_text(scope.fence_claimant, 512) &&
  scope.fence_generation > 0L &&
  scope.fence_generation < 9223372036854775807L &&
  valid_cid(scope.host_adoption_cid) &&
  valid_cid(scope.operation_occurrence_cid) &&
  valid_cid(scope.request_body_cid) &&
  valid_cid(scope.request_cid) &&
  valid_cid(scope.run_invocation_cid) &&
  valid_cid(scope.submission_scope_cid) &&
  valid_cid(scope.unit_definition_cid) &&
  bounded_text(scope.account_id, 512) &&
  bounded_text(scope.attempt_id, 256) &&
  bounded_text(scope.connector_registration, 512) &&
  bounded_text(scope.connector_revision, 512) &&
  bounded_text(scope.operation, 512) &&
  bounded_text(scope.principal, 512) &&
  ["GET", "POST", "PUT", "PATCH"].contains(scope.request_method) &&
  bounded_text(scope.request_path, 2048) &&
  scope.request_path.has_prefix("/") &&
  !scope.request_path.has_prefix("//") &&
  !scope.request_path.contains("?") &&
  !scope.request_path.contains("#") &&
  !scope.request_path.contains("\u{0}") &&
  valid_origin(scope.resource_origin) &&
  scope.resource_origin.length() > 8 &&
  !scope.resource_origin[8:].contains("/") &&
  !scope.resource_origin.contains("@") &&
  !scope.resource_origin.contains(" ") &&
  !scope.resource_origin.contains("\u{0}") &&
  (
    scope.request_method != "GET" ||
    scope.request_body_cid ==
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  )
}

///|
/// Identity of the exact finite transport body, independently of the checked
/// operation's semantic request CID. No text, JSON or configuration
/// normalization occurs here; Native send compares this with its isolated copy.
pub fn local_credential_request_body_cid(
  body : Bytes,
) -> Result[String, RemoteCredentialIssue] {
  if body.length() > 65536 {
    return Err(InvalidCredentialGrant)
  }
  Ok("sha256:" + @sha.hex(body))
}

///|
fn local_credential_grant_body(
  grant : LocalCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  let writer = @encode.writer(32768, 64, 2) catch {
    _ => return Err(InvalidCredentialGrant)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "account_configuration_cid")
    @encode.string_value(writer, grant.scope.account_configuration_cid)
    @encode.key(writer, "account_id")
    @encode.string_value(writer, grant.scope.account_id)
    @encode.key(writer, "attempt_id")
    @encode.string_value(writer, grant.scope.attempt_id)
    @encode.key(writer, "authority_scope_cid")
    @encode.string_value(writer, grant.scope.authority_scope_cid)
    @encode.key(writer, "connector_registration")
    @encode.string_value(writer, grant.scope.connector_registration)
    @encode.key(writer, "connector_revision")
    @encode.string_value(writer, grant.scope.connector_revision)
    @encode.key(writer, "expires_unix_ms")
    @encode.string_value(writer, grant.expires_unix_ms.to_string())
    @encode.key(writer, "fence_claimant")
    @encode.string_value(writer, grant.scope.fence_claimant)
    @encode.key(writer, "fence_generation")
    @encode.string_value(writer, grant.scope.fence_generation.to_string())
    @encode.key(writer, "fence_intent_cid")
    @encode.string_value(writer, grant.scope.fence_intent_cid)
    @encode.key(writer, "host_adoption_cid")
    @encode.string_value(writer, grant.scope.host_adoption_cid)
    @encode.key(writer, "issuer_authority")
    @encode.string_value(writer, grant.issuer_authority)
    @encode.key(writer, "max_uses")
    @encode.number_value(writer, grant.max_uses.to_double())
    @encode.key(writer, "operation")
    @encode.string_value(writer, grant.scope.operation)
    @encode.key(writer, "operation_occurrence_cid")
    @encode.string_value(writer, grant.scope.operation_occurrence_cid)
    @encode.key(writer, "principal")
    @encode.string_value(writer, grant.scope.principal)
    @encode.key(writer, "request_body_cid")
    @encode.string_value(writer, grant.scope.request_body_cid)
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, grant.scope.request_cid)
    @encode.key(writer, "request_method")
    @encode.string_value(writer, grant.scope.request_method)
    @encode.key(writer, "request_path")
    @encode.string_value(writer, grant.scope.request_path)
    @encode.key(writer, "resource_origin")
    @encode.string_value(writer, grant.scope.resource_origin)
    @encode.key(writer, "run_invocation_cid")
    @encode.string_value(writer, grant.scope.run_invocation_cid)
    @encode.key(writer, "submission_scope_cid")
    @encode.string_value(writer, grant.scope.submission_scope_cid)
    @encode.key(writer, "unit_definition_cid")
    @encode.string_value(writer, grant.scope.unit_definition_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-local-credential-grant/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
fn local_credential_grant_identity(
  grant : LocalCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  let body = match local_credential_grant_body(grant) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @sha.text_hex(body)
  .map(value => "sha256:" + value)
  .map_err(_ => InvalidCredentialGrant)
}

///|
/// Issue a bounded identity in the existing credential Owner. Installation,
/// current permissions, cancellation and durable send fencing are additional
/// Native Host checks; this constructor performs no use claim or Provider I/O.
pub fn prepare_local_credential_grant(
  issuer_authority : String,
  scope : LocalCredentialScope,
  expires_unix_ms : Int64,
  max_uses : Int,
) -> Result[LocalCredentialGrant, RemoteCredentialIssue] {
  if !bounded_text(issuer_authority, 512) ||
    !valid_local_credential_scope(scope) ||
    expires_unix_ms <= 0L ||
    max_uses < 1 ||
    max_uses > 1024 {
    return Err(InvalidCredentialGrant)
  }
  let pending : LocalCredentialGrant = {
    issuer_authority,
    scope,
    expires_unix_ms,
    max_uses,
    grant_cid: "pending",
  }
  local_credential_grant_identity(pending).map(cid => {
    ..pending,
    grant_cid: cid,
  })
}

///|
pub fn local_credential_grant_json(
  grant : LocalCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  let identity = match local_credential_grant_identity(grant) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != grant.grant_cid {
    return Err(CredentialGrantIdentityMismatch)
  }
  local_credential_grant_body(grant)
}

///|
pub fn local_credential_grant_cid(grant : LocalCredentialGrant) -> String {
  grant.grant_cid
}

///|
pub fn local_credential_grant_scope(
  grant : LocalCredentialGrant,
) -> LocalCredentialScope {
  grant.scope
}

///|
pub fn local_credential_grant_limits(
  grant : LocalCredentialGrant,
) -> (Int, Int64) {
  (grant.max_uses, grant.expires_unix_ms)
}

///|
pub fn admit_local_credential_grant_json(
  body : String,
  claimed_grant_cid : String,
) -> Result[LocalCredentialGrant, RemoteCredentialIssue] {
  try {
    let source = match
      @source.parse_json_bytes_preserving(@utf8.encode(body), {
        max_input_bytes: 32768,
        max_nodes: 64,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise RemoteCredentialDecodeStop
    }
    let cursor = credential_decoded(
      @decode.admit(source, {
        max_nodes: 64,
        max_depth: 2,
        max_string_bytes: 32768,
        max_total_string_bytes: 32768,
      }),
    )
    let object = credential_decoded(
      @decode.closed_object(cursor, [
        "account_configuration_cid", "account_id", "attempt_id", "authority_scope_cid",
        "connector_registration", "connector_revision", "fence_claimant", "fence_generation",
        "fence_intent_cid", "expires_unix_ms", "host_adoption_cid", "issuer_authority",
        "max_uses", "operation", "operation_occurrence_cid", "principal", "request_body_cid",
        "request_cid", "request_method", "request_path", "resource_origin", "run_invocation_cid",
        "submission_scope_cid", "unit_definition_cid", "version",
      ]),
    )
    if credential_text(object, "version") != "actql-local-credential-grant/0.1" {
      return Err(InvalidCredentialGrant)
    }
    let scope : LocalCredentialScope = {
      account_configuration_cid: credential_text(
        object, "account_configuration_cid",
      ),
      account_id: credential_text(object, "account_id"),
      attempt_id: credential_text(object, "attempt_id"),
      authority_scope_cid: credential_text(object, "authority_scope_cid"),
      connector_registration: credential_text(object, "connector_registration"),
      connector_revision: credential_text(object, "connector_revision"),
      fence_claimant: credential_text(object, "fence_claimant"),
      fence_generation: credential_int64_text(
        credential_text(object, "fence_generation"),
      ),
      fence_intent_cid: credential_text(object, "fence_intent_cid"),
      host_adoption_cid: credential_text(object, "host_adoption_cid"),
      operation: credential_text(object, "operation"),
      operation_occurrence_cid: credential_text(
        object, "operation_occurrence_cid",
      ),
      principal: credential_text(object, "principal"),
      request_body_cid: credential_text(object, "request_body_cid"),
      request_cid: credential_text(object, "request_cid"),
      request_method: credential_text(object, "request_method"),
      request_path: credential_text(object, "request_path"),
      resource_origin: credential_text(object, "resource_origin"),
      run_invocation_cid: credential_text(object, "run_invocation_cid"),
      submission_scope_cid: credential_text(object, "submission_scope_cid"),
      unit_definition_cid: credential_text(object, "unit_definition_cid"),
    }
    let grant = match
      prepare_local_credential_grant(
        credential_text(object, "issuer_authority"),
        scope,
        credential_int64_text(credential_text(object, "expires_unix_ms")),
        credential_int(object, "max_uses"),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if local_credential_grant_json(grant) != Ok(body) {
      return Err(InvalidCredentialGrant)
    }
    if grant.grant_cid != claimed_grant_cid {
      return Err(CredentialGrantIdentityMismatch)
    }
    Ok(grant)
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}
