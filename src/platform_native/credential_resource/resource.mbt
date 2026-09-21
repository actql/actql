///|
pub(all) enum NativeCredentialResourceIssue {
  InvalidConfiguration
  AccessDenied
  UseAlreadyClaimed
  ResourceRejected(Int)
  Credential(@credential.RemoteCredentialIssue)
  Signature(@signature.NativeSignatureIssue)
  Journal(@sqlite.NativeSqliteIssue)
  Transport(@http.NativeHttpIssue)
  TrustedClockRollback
  TerminalRecordFailed(String, @sqlite.NativeSqliteIssue)
}

///|
pub(all) struct NativeCredentialAuthority {
  issuer_authority : String
  key_id : String
  public_key_pem : String
  admit_new_grants : Bool
}

///|
pub(all) struct NativeCredentialScope {
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
}

///|
pub(all) struct NativeCredentialOperation {
  resource_origin : String
  operation : String
  path : String
  secret_path : String
}

///|
pub(all) struct NativeCredentialAuthorization {
  stage : String
  grant_cid : String
  use_cid : String?
  scope : NativeCredentialScope
}

///|
pub(all) struct NativeCredentialResponse {
  use_cid : String
  status : Int
  body : Bytes
}

///|
pub(all) struct NativeCredentialUseStatus {
  use_cid : String
  outcome : String
  status : Int?
}

///|
struct NativeCredentialResourceService {
  database : @sqlite.Database
  client : @http.Client
  operations : Array[NativeCredentialOperation]
  authorize : (NativeCredentialAuthorization) -> Bool
  clock : () -> Int64
}

///|
fn valid_origin(value : String) -> Bool {
  if !value.has_prefix("https://") ||
    value.length() <= 8 ||
    value.length() > 2048 ||
    value.contains("\u{0}") ||
    value.contains("?") ||
    value.contains("#") ||
    value.contains("@") {
    return false
  }
  let authority = value.unsafe_substring(start=8, end=value.length())
  !authority.is_empty() && !authority.contains("/") && !authority.contains(" ")
}

///|
fn valid_operation(value : NativeCredentialOperation) -> Bool {
  valid_origin(value.resource_origin) &&
  !value.operation.is_empty() &&
  value.operation.length() <= 512 &&
  value.path.has_prefix("/") &&
  !value.path.has_prefix("//") &&
  value.path.length() <= 2048 &&
  !value.path.contains("?") &&
  !value.path.contains("#") &&
  !value.path.contains("\u{0}") &&
  !value.secret_path.is_empty() &&
  value.secret_path.length() <= 4096 &&
  !value.secret_path.contains("\u{0}")
}

///|
pub fn admit_signed_native_credential_grant(
  library : @signature.Library,
  envelope : @credential.RemoteCredentialSignatureEnvelope,
  authorities : Array[NativeCredentialAuthority],
) -> Result[@credential.RemoteCredentialGrant, NativeCredentialResourceIssue] {
  let projection = @credential.credential_signature_envelope_projection(
    envelope,
  )
  if projection.length() != 6 {
    return Err(Credential(@credential.InvalidCredentialSignature))
  }
  let mut public_key = None
  for authority in authorities {
    if authority.admit_new_grants &&
      authority.issuer_authority == projection[5] &&
      authority.key_id == projection[1] {
      if public_key is Some(_) {
        return Err(Credential(@credential.InvalidCredentialSignature))
      }
      public_key = Some(authority.public_key_pem)
    }
  }
  guard public_key is Some(key) else {
    return Err(Credential(@credential.InvalidCredentialSignature))
  }
  let grant = @credential.credential_signature_envelope_grant(envelope)
  let preimage = match @credential.credential_grant_signature_preimage(grant) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  match library.verify_ed25519(key, preimage, projection[4]) {
    Ok(true) => Ok(grant)
    Ok(false) => Err(Credential(@credential.InvalidCredentialSignature))
    Err(issue) => Err(Signature(issue))
  }
}

///|
fn operation_for(
  service : NativeCredentialResourceService,
  scope : NativeCredentialScope,
) -> NativeCredentialOperation? {
  let mut found = None
  for operation in service.operations {
    if operation.resource_origin == scope.resource_origin &&
      operation.operation == scope.operation {
      if found is Some(_) {
        return None
      }
      found = Some(operation)
    }
  }
  found
}

///|
fn parse_positive_int(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for index = 0; index < value.length(); index = index + 1 {
    let digit = value[index].to_int() - 48
    if digit < 0 || digit > 9 || result > (2147483647 - digit) / 10 {
      return None
    }
    result = result * 10 + digit
  }
  if result > 0 {
    Some(result)
  } else {
    None
  }
}

///|
fn parse_positive_int64(value : String) -> Int64? {
  if value.is_empty() {
    return None
  }
  let mut result = 0L
  for index = 0; index < value.length(); index = index + 1 {
    let digit = value[index].to_int() - 48
    if digit < 0 ||
      digit > 9 ||
      result > (9223372036854775807L - digit.to_int64()) / 10L {
      return None
    }
    result = result * 10L + digit.to_int64()
  }
  if result > 0L {
    Some(result)
  } else {
    None
  }
}

///|
fn first_newline(value : String) -> Int? {
  for index = 0; index < value.length(); index = index + 1 {
    if value[index].to_int() == 10 {
      return Some(index)
    }
  }
  None
}

///|
fn grant_matches_scope(
  grant : @credential.RemoteCredentialGrant,
  scope : NativeCredentialScope,
) -> (Int, Int64)? {
  let fields = @credential.credential_grant_projection(grant)
  guard fields.length() == 17 &&
    fields[2] == scope.principal &&
    fields[3] == scope.tenant &&
    fields[4] == scope.environment &&
    fields[5] == scope.site_key &&
    fields[6] == scope.site_generation.to_string() &&
    fields[7] == scope.runtime_bundle_cid &&
    fields[8] == scope.connector_registration &&
    fields[9] == scope.connector_revision &&
    fields[10] == scope.resource_origin &&
    fields[11] == scope.operation &&
    fields[12] == scope.run_invocation_cid &&
    fields[13] == scope.task_attempt.to_string() &&
    fields[14] == scope.dispatch_request_cid else {
    return None
  }
  guard parse_positive_int(fields[16]) is Some(max_uses) &&
    parse_positive_int64(fields[15]) is Some(expires_at) else {
    return None
  }
  Some((max_uses, expires_at))
}

///|
fn use_scope(grant_cid : String) -> String {
  "native-credential-use:" + grant_cid
}

///|
fn outcome_scope(grant_cid : String) -> String {
  "native-credential-outcome:" + grant_cid
}

///|
fn revocation_scope() -> String {
  "native-credential-revocation"
}

///|
fn native_credential_grant_revoked(
  service : NativeCredentialResourceService,
  grant_cid : String,
) -> Result[Bool, NativeCredentialResourceIssue] {
  match service.database.read(revocation_scope(), grant_cid) {
    Err(@sqlite.NotFound) => Ok(false)
    Err(issue) => Err(Journal(issue))
    Ok(value) =>
      if value.body == @utf8.encode(grant_cid) {
        Ok(true)
      } else {
        Err(Journal(@sqlite.Collision))
      }
  }
}

///|
pub fn revoke_native_credential_grant(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
) -> Result[Unit, NativeCredentialResourceIssue] {
  let grant_cid = @credential.credential_grant_cid(grant)
  let body = @utf8.encode(grant_cid)
  match service.database.insert(revocation_scope(), grant_cid, body) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) =>
      match service.database.read(revocation_scope(), grant_cid) {
        Ok(existing) if existing.body == body => Ok(())
        Ok(_) => Err(Journal(@sqlite.Collision))
        Err(issue) => Err(Journal(issue))
      }
    Err(issue) => Err(Journal(issue))
  }
}

///|
fn persist_outcome(
  service : NativeCredentialResourceService,
  grant_cid : String,
  use_id : String,
  outcome : String,
  status : Int?,
) -> Result[Unit, NativeCredentialResourceIssue] {
  let body = @utf8.encode(
    outcome + "\n" + status.map(value => value.to_string()).unwrap_or(""),
  )
  match service.database.insert(outcome_scope(grant_cid), use_id, body) {
    Ok(_) => Ok(())
    Err(@sqlite.Collision) =>
      match service.database.read(outcome_scope(grant_cid), use_id) {
        Ok(existing) if existing.body == body => Ok(())
        Ok(_) => Err(Journal(@sqlite.Collision))
        Err(issue) => Err(Journal(issue))
      }
    Err(issue) => Err(Journal(issue))
  }
}

///|
fn install_native_credential_resource_service_with_clock(
  database : @sqlite.Database,
  client : @http.Client,
  operations : Array[NativeCredentialOperation],
  authorize : (NativeCredentialAuthorization) -> Bool,
  clock : () -> Int64,
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  if operations.is_empty() ||
    operations.any(operation => !valid_operation(operation)) {
    return Err(InvalidConfiguration)
  }
  for index, operation in operations {
    for prior = 0; prior < index; prior = prior + 1 {
      if operations[prior].resource_origin == operation.resource_origin &&
        operations[prior].operation == operation.operation {
        return Err(InvalidConfiguration)
      }
    }
  }
  Ok({ database, client, operations, authorize, clock, })
}

///|
pub fn install_native_credential_resource_service(
  database : @sqlite.Database,
  client : @http.Client,
  operations : Array[NativeCredentialOperation],
  authorize : (NativeCredentialAuthorization) -> Bool,
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  install_native_credential_resource_service_with_clock(
    database,
    client,
    operations,
    authorize,
    fn() { @env.now().reinterpret_as_int64() },
  )
}

///|
fn observe_trusted_clock(
  service : NativeCredentialResourceService,
) -> Result[Int64, NativeCredentialResourceIssue] {
  let observed = (service.clock)()
  if observed < 0L {
    return Err(TrustedClockRollback)
  }
  let scope = "credential-clock-v1"
  let key = "host-lower-bound"
  let body = @utf8.encode(observed.to_string())
  for attempt = 0; attempt < 8; attempt = attempt + 1 {
    match service.database.read(scope, key) {
      Ok(existing) => {
        let previous = match parse_positive_int64(@utf8.decode_lossy(existing.body)) {
          Some(value) => value
          None => return Err(Journal(@sqlite.Collision))
        }
        if observed < previous {
          return Err(TrustedClockRollback)
        }
        if observed == previous {
          return Ok(observed)
        }
        match service.database.compare_exchange(
          scope,
          key,
          existing.revision,
          body,
        ) {
          Ok(_) => return Ok(observed)
          Err(@sqlite.Collision) | Err(@sqlite.Busy) => continue
          Err(issue) => return Err(Journal(issue))
        }
      }
      Err(@sqlite.NotFound) =>
        match service.database.insert(scope, key, body) {
          Ok(_) => return Ok(observed)
          Err(@sqlite.Collision) | Err(@sqlite.Busy) => continue
          Err(issue) => return Err(Journal(issue))
        }
      Err(issue) => return Err(Journal(issue))
    }
  }
  Err(Journal(@sqlite.Busy))
}

///|
pub fn call_native_credential_resource(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  let trusted_now_ms = match observe_trusted_clock(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let grant_cid = @credential.credential_grant_cid(grant)
  let revoked = match native_credential_grant_revoked(service, grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard !revoked &&
    operation_for(service, scope) is Some(operation) &&
    grant_matches_scope(grant, scope) is Some((max_uses, expires_at)) &&
    !use_id.is_empty() &&
    use_id.length() <= 256 &&
    trusted_now_ms >= 0L &&
    trusted_now_ms < expires_at else {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  if !(service.authorize)({ stage: "claim", grant_cid, use_cid: None, scope, }) {
    return Err(AccessDenied)
  }
  let ordinal = match
    service.database.claim_ordinal(
      use_scope(grant_cid),
      use_id,
      max_uses.to_int64(),
    ) {
    Ok(value) if value <= 2147483647L => value.to_int()
    Ok(_) => return Err(InvalidConfiguration)
    Err(issue) => return Err(Journal(issue))
  }
  let credential_use = match
    @credential.prepare_credential_use(
      grant,
      use_id,
      trusted_now_ms,
      ordinal - 1,
      revoked,
      scope.principal,
      scope.tenant,
      scope.environment,
      scope.site_key,
      scope.site_generation,
      scope.runtime_bundle_cid,
      scope.connector_registration,
      scope.connector_revision,
      scope.resource_origin,
      scope.operation,
      scope.run_invocation_cid,
      scope.task_attempt,
      scope.dispatch_request_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  let use_cid = @credential.credential_use_cid(credential_use)
  let use_body = match @credential.credential_use_json(credential_use) {
    Ok(value) => @utf8.encode(use_cid + "\n" + value)
    Err(issue) => return Err(Credential(issue))
  }
  match service.database.insert(use_scope(grant_cid), use_id, use_body) {
    Ok(_) => ()
    Err(@sqlite.Collision) => {
      let existing = match service.database.read(use_scope(grant_cid), use_id) {
        Ok(value) => value
        Err(issue) => return Err(Journal(issue))
      }
      if existing.body != use_body {
        return Err(Journal(@sqlite.Collision))
      }
      return Err(UseAlreadyClaimed)
    }
    Err(issue) => return Err(Journal(issue))
  }
  let send_time = match observe_trusted_clock(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authorized = send_time < expires_at && (service.authorize)({
      stage: "send",
      grant_cid,
      use_cid: Some(use_cid),
      scope,
    }) &&
    @credential.authorize_credential_use(
      credential_use,
      send_time,
      revoked,
      scope.principal,
      scope.tenant,
      scope.environment,
      scope.site_key,
      scope.site_generation,
      scope.runtime_bundle_cid,
      scope.connector_registration,
      scope.connector_revision,
      scope.resource_origin,
      scope.operation,
      scope.run_invocation_cid,
      scope.task_attempt,
      scope.dispatch_request_cid,
    )
    is Ok(_)
  if !authorized {
    match persist_outcome(service, grant_cid, use_id, "failed", None) {
      Ok(_) => return Err(AccessDenied)
      Err(Journal(issue)) => return Err(TerminalRecordFailed("failed", issue))
      Err(issue) => return Err(issue)
    }
  }
  let response = match
    service.client.get_bearer_file(
      operation.resource_origin + operation.path,
      operation.secret_path,
      expires_at,
    ) {
    Ok(value) => value
    Err(issue) =>
      match persist_outcome(service, grant_cid, use_id, "unknown", None) {
        Ok(_) => return Err(Transport(issue))
        Err(Journal(journal_issue)) =>
          return Err(TerminalRecordFailed("unknown", journal_issue))
        Err(other) => return Err(other)
      }
  }
  if response.status < 200 || response.status >= 300 {
    match
      persist_outcome(
        service,
        grant_cid,
        use_id,
        "failed",
        Some(response.status),
      ) {
      Ok(_) => return Err(ResourceRejected(response.status))
      Err(Journal(issue)) => return Err(TerminalRecordFailed("failed", issue))
      Err(other) => return Err(other)
    }
  }
  match
    persist_outcome(
      service,
      grant_cid,
      use_id,
      "succeeded",
      Some(response.status),
    ) {
    Err(Journal(issue)) => return Err(TerminalRecordFailed("succeeded", issue))
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok({ use_cid, status: response.status, body: response.body, })
}

///|
pub fn query_native_credential_use(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
) -> Result[NativeCredentialUseStatus, NativeCredentialResourceIssue] {
  guard operation_for(service, scope) is Some(_) &&
    grant_matches_scope(grant, scope) is Some(_) &&
    !use_id.is_empty() &&
    use_id.length() <= 256 else {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  let grant_cid = @credential.credential_grant_cid(grant)
  if !(service.authorize)({ stage: "query", grant_cid, use_cid: None, scope, }) {
    return Err(AccessDenied)
  }
  let use_record = match service.database.read(use_scope(grant_cid), use_id) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let use_record_text = @utf8.decode(use_record.body) catch {
    _ => return Err(Journal(@sqlite.Collision))
  }
  guard first_newline(use_record_text) is Some(use_separator) else {
    return Err(Journal(@sqlite.Collision))
  }
  let use_cid = use_record_text.unsafe_substring(start=0, end=use_separator)
  let use_json = use_record_text.unsafe_substring(
    start=use_separator + 1,
    end=use_record_text.length(),
  )
  let admitted_use = match
    @credential.admit_credential_use_json(grant, use_json, use_cid) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  if @credential.credential_use_projection(admitted_use)[2] != use_id {
    return Err(Journal(@sqlite.Collision))
  }
  if !(service.authorize)({
      stage: "return",
      grant_cid,
      use_cid: Some(use_cid),
      scope,
    }) {
    return Err(AccessDenied)
  }
  let outcome = match service.database.read(outcome_scope(grant_cid), use_id) {
    Err(@sqlite.NotFound) =>
      return Ok({ use_cid, outcome: "claimed", status: None, })
    Err(issue) => return Err(Journal(issue))
    Ok(value) =>
      @utf8.decode(value.body) catch {
        _ => return Err(Journal(@sqlite.Collision))
      }
  }
  let newline = first_newline(outcome)
  guard newline is Some(index) else { return Err(Journal(@sqlite.Collision)) }
  let name = outcome.unsafe_substring(start=0, end=index)
  let status_text = outcome.unsafe_substring(
    start=index + 1,
    end=outcome.length(),
  )
  let status = if status_text.is_empty() {
    None
  } else {
    parse_positive_int(status_text)
  }
  if name != "succeeded" && name != "failed" && name != "unknown" {
    return Err(Journal(@sqlite.Collision))
  }
  Ok({ use_cid, outcome: name, status, })
}
