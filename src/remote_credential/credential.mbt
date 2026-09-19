///|
pub(all) enum RemoteCredentialIssue {
  InvalidCredentialGrant
  CredentialGrantIdentityMismatch
  CredentialGrantInactive
  CredentialUseCollision
} derive(Eq, Debug)

///|
/// A credential grant authorizes one registered operation scope. It never
/// contains the provider secret and does not itself prove that a call ran.
struct RemoteCredentialGrant {
  issuer_authority : String
  principal : String
  tenant : String
  environment : String
  site_key : String
  site_generation : Int
  runtime_bundle_cid : String
  connector_registration : String
  connector_revision : String
  resource_origin : String
  operation : String
  run_invocation_cid : String
  task_attempt : Int
  dispatch_request_cid : String
  expires_unix_ms : Int64
  max_uses : Int
  grant_cid : String
}

///|
/// One durable use occurrence consumes its ordinal before external I/O.
struct RemoteCredentialUse {
  grant : RemoteCredentialGrant
  use_id : String
  use_ordinal : Int
  use_cid : String
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn bounded_text(value : String, maximum : Int) -> Bool {
  !value.is_empty() && value.length() <= maximum
}

///|
fn valid_origin(value : String) -> Bool {
  bounded_text(value, 2048) &&
  value.has_prefix("https://") &&
  !value.contains("#") &&
  !value.contains("?")
}

///|
fn valid_grant_fields(grant : RemoteCredentialGrant) -> Bool {
  bounded_text(grant.issuer_authority, 512) &&
  bounded_text(grant.principal, 512) &&
  bounded_text(grant.tenant, 512) &&
  bounded_text(grant.environment, 512) &&
  bounded_text(grant.site_key, 512) &&
  grant.site_generation >= 0 &&
  valid_cid(grant.runtime_bundle_cid) &&
  bounded_text(grant.connector_registration, 512) &&
  bounded_text(grant.connector_revision, 512) &&
  valid_origin(grant.resource_origin) &&
  bounded_text(grant.operation, 512) &&
  valid_cid(grant.run_invocation_cid) &&
  grant.task_attempt >= 0 &&
  valid_cid(grant.dispatch_request_cid) &&
  grant.expires_unix_ms > 0L &&
  grant.max_uses > 0
}

///|
fn grant_body(
  grant : RemoteCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  let writer = @encode.writer(32768, 40, 2) catch {
    _ => return Err(InvalidCredentialGrant)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "connector_registration")
    @encode.string_value(writer, grant.connector_registration)
    @encode.key(writer, "connector_revision")
    @encode.string_value(writer, grant.connector_revision)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, grant.dispatch_request_cid)
    @encode.key(writer, "environment")
    @encode.string_value(writer, grant.environment)
    @encode.key(writer, "expires_unix_ms")
    @encode.string_value(writer, grant.expires_unix_ms.to_string())
    @encode.key(writer, "issuer_authority")
    @encode.string_value(writer, grant.issuer_authority)
    @encode.key(writer, "max_uses")
    @encode.number_value(writer, grant.max_uses.to_double())
    @encode.key(writer, "operation")
    @encode.string_value(writer, grant.operation)
    @encode.key(writer, "principal")
    @encode.string_value(writer, grant.principal)
    @encode.key(writer, "resource_origin")
    @encode.string_value(writer, grant.resource_origin)
    @encode.key(writer, "run_invocation_cid")
    @encode.string_value(writer, grant.run_invocation_cid)
    @encode.key(writer, "runtime_bundle_cid")
    @encode.string_value(writer, grant.runtime_bundle_cid)
    @encode.key(writer, "site_generation")
    @encode.number_value(writer, grant.site_generation.to_double())
    @encode.key(writer, "site_key")
    @encode.string_value(writer, grant.site_key)
    @encode.key(writer, "task_attempt")
    @encode.number_value(writer, grant.task_attempt.to_double())
    @encode.key(writer, "tenant")
    @encode.string_value(writer, grant.tenant)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-credential-grant/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
fn grant_identity(
  grant : RemoteCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  let body = match grant_body(grant) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidCredentialGrant)
  }
}

///|
pub fn prepare_grant(
  issuer_authority : String,
  principal : String,
  tenant : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  operation : String,
  run_invocation_cid : String,
  task_attempt : Int,
  dispatch_request_cid : String,
  expires_unix_ms : Int64,
  max_uses : Int,
) -> Result[RemoteCredentialGrant, RemoteCredentialIssue] {
  let pending : RemoteCredentialGrant = {
    issuer_authority,
    principal,
    tenant,
    environment,
    site_key,
    site_generation,
    runtime_bundle_cid,
    connector_registration,
    connector_revision,
    resource_origin,
    operation,
    run_invocation_cid,
    task_attempt,
    dispatch_request_cid,
    expires_unix_ms,
    max_uses,
    grant_cid: "pending",
  }
  if !valid_grant_fields(pending) {
    return Err(InvalidCredentialGrant)
  }
  let identity = match grant_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, grant_cid: identity, })
}

///|
priv suberror RemoteCredentialDecodeStop {
  RemoteCredentialDecodeStop
}

///|
fn[T] credential_decoded(
  value : Result[T, @decode.Issue],
) -> T raise RemoteCredentialDecodeStop {
  match value {
    Ok(result) => result
    Err(_) => raise RemoteCredentialDecodeStop
  }
}

///|
fn credential_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise RemoteCredentialDecodeStop {
  credential_decoded(
    @decode.text(credential_decoded(@decode.required(object, key))),
  )
}

///|
fn credential_int(
  object : @decode.ObjectView,
  key : String,
) -> Int raise RemoteCredentialDecodeStop {
  let value = credential_decoded(
    @decode.safe_integer(credential_decoded(@decode.required(object, key))),
  )
  if value < 0L || value > 2147483647L {
    raise RemoteCredentialDecodeStop
  }
  value.to_int()
}

///|
fn credential_int64_text(
  value : String,
) -> Int64 raise RemoteCredentialDecodeStop {
  if value.is_empty() {
    raise RemoteCredentialDecodeStop
  }
  let mut result = 0L
  for index = 0; index < value.length(); index = index + 1 {
    let digit = value[index].to_int() - 48
    if digit < 0 ||
      digit > 9 ||
      result > (9223372036854775807L - digit.to_int64()) / 10L {
      raise RemoteCredentialDecodeStop
    }
    result = result * 10L + digit.to_int64()
  }
  result
}

///|
fn admit_grant_body(
  body : String,
) -> RemoteCredentialGrant raise RemoteCredentialDecodeStop {
  let bytes = @utf8.encode(body)
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: 32768,
      max_nodes: 40,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => raise RemoteCredentialDecodeStop
  }
  let cursor = credential_decoded(
    @decode.admit(node, {
      max_nodes: 40,
      max_depth: 2,
      max_string_bytes: 32768,
      max_total_string_bytes: 32768,
    }),
  )
  let object = credential_decoded(
    @decode.closed_object(cursor, [
      "connector_registration", "connector_revision", "dispatch_request_cid", "environment",
      "expires_unix_ms", "issuer_authority", "max_uses", "operation", "principal",
      "resource_origin", "run_invocation_cid", "runtime_bundle_cid", "site_generation",
      "site_key", "task_attempt", "tenant", "version",
    ]),
  )
  if credential_text(object, "version") != "actql-remote-credential-grant/0.1" {
    raise RemoteCredentialDecodeStop
  }
  let grant = match
    prepare_grant(
      credential_text(object, "issuer_authority"),
      credential_text(object, "principal"),
      credential_text(object, "tenant"),
      credential_text(object, "environment"),
      credential_text(object, "site_key"),
      credential_int(object, "site_generation"),
      credential_text(object, "runtime_bundle_cid"),
      credential_text(object, "connector_registration"),
      credential_text(object, "connector_revision"),
      credential_text(object, "resource_origin"),
      credential_text(object, "operation"),
      credential_text(object, "run_invocation_cid"),
      credential_int(object, "task_attempt"),
      credential_text(object, "dispatch_request_cid"),
      credential_int64_text(credential_text(object, "expires_unix_ms")),
      credential_int(object, "max_uses"),
    ) {
    Ok(value) => value
    Err(_) => raise RemoteCredentialDecodeStop
  }
  if credential_grant_json(grant) != Ok(body) {
    raise RemoteCredentialDecodeStop
  }
  grant
}

///|
pub fn admit_grant_json(
  body : String,
  claimed_grant_cid : String,
) -> Result[RemoteCredentialGrant, RemoteCredentialIssue] {
  try {
    let grant = admit_grant_body(body)
    if grant.grant_cid == claimed_grant_cid {
      Ok(grant)
    } else {
      Err(CredentialGrantIdentityMismatch)
    }
  } catch {
    RemoteCredentialDecodeStop => Err(InvalidCredentialGrant)
  }
}

///|
pub fn credential_grant_cid(grant : RemoteCredentialGrant) -> String {
  grant.grant_cid
}

///|
pub fn credential_grant_json(
  grant : RemoteCredentialGrant,
) -> Result[String, RemoteCredentialIssue] {
  if !valid_grant_fields(grant) {
    return Err(InvalidCredentialGrant)
  }
  let identity = match grant_identity(grant) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != grant.grant_cid {
    return Err(CredentialGrantIdentityMismatch)
  }
  grant_body(grant)
}

///|
pub fn credential_grant_projection(
  grant : RemoteCredentialGrant,
) -> Array[String] {
  [
    grant.grant_cid,
    grant.issuer_authority,
    grant.principal,
    grant.tenant,
    grant.environment,
    grant.site_key,
    grant.site_generation.to_string(),
    grant.runtime_bundle_cid,
    grant.connector_registration,
    grant.connector_revision,
    grant.resource_origin,
    grant.operation,
    grant.run_invocation_cid,
    grant.task_attempt.to_string(),
    grant.dispatch_request_cid,
    grant.expires_unix_ms.to_string(),
    grant.max_uses.to_string(),
  ]
}

///|
fn use_body(
  credential_use : RemoteCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  let writer = @encode.writer(4096, 12, 2) catch {
    _ => return Err(InvalidCredentialGrant)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "grant_cid")
    @encode.string_value(writer, credential_use.grant.grant_cid)
    @encode.key(writer, "use_id")
    @encode.string_value(writer, credential_use.use_id)
    @encode.key(writer, "use_ordinal")
    @encode.number_value(writer, credential_use.use_ordinal.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-credential-use/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidCredentialGrant)
  }
}

///|
fn use_identity(
  credential_use : RemoteCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  let body = match use_body(credential_use) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match @sha.text_hex(body) {
    Ok(value) => Ok("sha256:" + value)
    Err(_) => Err(InvalidCredentialGrant)
  }
}

///|
pub fn prepare_credential_use(
  grant : RemoteCredentialGrant,
  use_id : String,
  trusted_now_ms : Int64,
  used_count : Int,
  revoked : Bool,
  principal : String,
  tenant : String,
  environment : String,
  site_key : String,
  site_generation : Int,
  runtime_bundle_cid : String,
  connector_registration : String,
  connector_revision : String,
  resource_origin : String,
  operation : String,
  run_invocation_cid : String,
  task_attempt : Int,
  dispatch_request_cid : String,
) -> Result[RemoteCredentialUse, RemoteCredentialIssue] {
  if !valid_grant_fields(grant) ||
    credential_grant_json(grant) is Err(_) ||
    !bounded_text(use_id, 256) ||
    trusted_now_ms < 0L ||
    trusted_now_ms >= grant.expires_unix_ms ||
    used_count < 0 ||
    used_count >= grant.max_uses ||
    revoked ||
    principal != grant.principal ||
    tenant != grant.tenant ||
    environment != grant.environment ||
    site_key != grant.site_key ||
    site_generation != grant.site_generation ||
    runtime_bundle_cid != grant.runtime_bundle_cid ||
    connector_registration != grant.connector_registration ||
    connector_revision != grant.connector_revision ||
    resource_origin != grant.resource_origin ||
    operation != grant.operation ||
    run_invocation_cid != grant.run_invocation_cid ||
    task_attempt != grant.task_attempt ||
    dispatch_request_cid != grant.dispatch_request_cid {
    return Err(CredentialGrantInactive)
  }
  let pending : RemoteCredentialUse = {
    grant,
    use_id,
    use_ordinal: used_count + 1,
    use_cid: "pending",
  }
  let identity = match use_identity(pending) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ ..pending, use_cid: identity, })
}

///|
pub fn credential_use_cid(credential_use : RemoteCredentialUse) -> String {
  credential_use.use_cid
}

///|
pub fn credential_use_json(
  credential_use : RemoteCredentialUse,
) -> Result[String, RemoteCredentialIssue] {
  let identity = match use_identity(credential_use) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity != credential_use.use_cid {
    return Err(CredentialUseCollision)
  }
  use_body(credential_use)
}

///|
pub fn credential_use_projection(
  credential_use : RemoteCredentialUse,
) -> Array[String] {
  [
    credential_use.use_cid,
    credential_use.grant.grant_cid,
    credential_use.use_id,
    credential_use.use_ordinal.to_string(),
  ]
}
