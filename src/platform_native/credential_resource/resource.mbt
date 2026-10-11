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
  RawObservation(@publication.NativePublicationStoreIssue)
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
  namespace_id : String
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
  verb : @http.NativeHttpMethod
  max_request_bytes : Int
}

///|
pub(all) struct NativeCredentialAuthorization {
  stage : String
  grant_cid : String
  use_cid : String?
  scope : NativeCredentialScope
  request : NativeCredentialRequest?
}

///|
/// Exact bytes presented to the current authorization callback. The caller
/// must obtain these from its checked request Owner, not from an untrusted
/// Program or an approval for a different target.
pub(all) struct NativeCredentialRequest {
  verb : @http.NativeHttpMethod
  path : String
  body : Bytes
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
  authorize_local : ((NativeLocalCredentialAuthorization) -> Bool)?
  authorize_preparation : ((NativeLocalPreparationCredentialAuthorization) -> Bool)?
  preparation_installations : Array[
    NativeLocalPreparationCredentialInstallation,
  ]
  preparation_raw_store : NativeLocalPreparationRawStore?
  retain_remote_use : ((@credential.RemoteCredentialUse) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ])?
  claim_initial_remote_use : ((@credential.RemoteCredentialGrant, String, NativeCredentialScope) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ])?
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
  value.max_request_bytes >= 0 &&
  value.max_request_bytes <= 65536 &&
  (value.verb != @http.Get || value.max_request_bytes == 0) &&
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
    fields[3] == scope.namespace_id &&
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
  read_credential_grant_revocation(service.database, grant_cid)
}

///|
// Shared original-journal observation. A read-only recovery does not install
// a transport client or acquire another credential use to inspect revocation.
fn read_credential_grant_revocation(
  database : @sqlite.Database,
  grant_cid : String,
) -> Result[Bool, NativeCredentialResourceIssue] {
  match database.read(revocation_scope(), grant_cid) {
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
  revoke_native_owned_credential_grant(service, grant_cid)
}

///|
fn revoke_native_owned_credential_grant(
  service : NativeCredentialResourceService,
  grant_cid : String,
) -> Result[Unit, NativeCredentialResourceIssue] {
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
  authorize_local? : ((NativeLocalCredentialAuthorization) -> Bool)? = None,
  authorize_preparation? : ((NativeLocalPreparationCredentialAuthorization) -> Bool)? = None,
  preparation_installations? : Array[
    NativeLocalPreparationCredentialInstallation,
  ] = [],
  preparation_raw_store? : NativeLocalPreparationRawStore? = None,
  retain_remote_use? : ((@credential.RemoteCredentialUse) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ])? = None,
  claim_initial_remote_use? : ((@credential.RemoteCredentialGrant, String, NativeCredentialScope) -> Result[
    Unit,
    NativeCredentialResourceIssue,
  ])? = None,
) -> Result[NativeCredentialResourceService, NativeCredentialResourceIssue] {
  if claim_initial_remote_use is Some(_) && retain_remote_use is None {
    return Err(InvalidConfiguration)
  }
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
  Ok({
    database,
    client,
    operations: operations.map(value => value),
    authorize,
    authorize_local,
    authorize_preparation,
    preparation_installations: preparation_installations.map(value => value),
    preparation_raw_store,
    retain_remote_use,
    claim_initial_remote_use,
    clock,
  })
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
  observe_credential_journal_clock(service.database, observed)
}

///|
fn observe_credential_journal_clock(
  database : @sqlite.Database,
  observed : Int64,
) -> Result[Int64, NativeCredentialResourceIssue] {
  match
    @trusted_clock.advance_lower_bound(
      database, "credential-clock-v1", "host-lower-bound", observed,
    ) {
    Ok(value) => Ok(value)
    Err(@trusted_clock.Rollback) | Err(@trusted_clock.InvalidConfiguration) =>
      Err(TrustedClockRollback)
    Err(@trusted_clock.Physical(issue)) => Err(Journal(issue))
    Err(@trusted_clock.Closed) => Err(Journal(@sqlite.DatabaseClosed))
  }
}

///|
pub fn call_native_credential_resource(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned(
    service,
    grant,
    use_id,
    scope,
    None,
    @http.Get,
    b"",
    None,
  )
}

///|
/// Require the checked target path to match the installed operation before
/// authorization, durable grant consumption or physical I/O. This cannot widen
/// the installation's allowlist or replace its current authorization checks.
pub fn call_native_credential_resource_at_path(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
  expected_path : String,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned(
    service,
    grant,
    use_id,
    scope,
    Some(expected_path),
    @http.Get,
    b"",
    None,
  )
}

///|
/// Send one exact installed operation through the existing durable credential
/// use Owner. A claim is never permission to resend after a failed or uncertain
/// response. Effect callers must additionally claim their common Effect Ledger.
pub fn call_native_credential_resource_request_at_path(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
  verb : @http.NativeHttpMethod,
  expected_path : String,
  body : Bytes,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned(
    service,
    grant,
    use_id,
    scope,
    Some(expected_path),
    verb,
    body,
    None,
  )
}

///|
/// Keep an installed caller's current execution fence separate from credential
/// authorization. Check it after Host callbacks, before consuming a use and
/// again after the final clock observation immediately before physical I/O.
/// This guard cannot replace the credential grant, exact request allowlist or
/// the caller's durable Effect claim. A false final guard does not permit replay.
pub fn call_native_credential_resource_guarded_request_at_path(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
  verb : @http.NativeHttpMethod,
  expected_path : String,
  body : Bytes,
  current : () -> Bool,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned(
    service,
    grant,
    use_id,
    scope,
    Some(expected_path),
    verb,
    body,
    Some(current),
  )
}

///|
fn call_native_credential_resource_owned(
  service : NativeCredentialResourceService,
  grant : @credential.RemoteCredentialGrant,
  use_id : String,
  scope : NativeCredentialScope,
  expected_path : String?,
  verb : @http.NativeHttpMethod,
  body : Bytes,
  current : (() -> Bool)?,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  call_native_credential_resource_owned_scope(
    service,
    RemoteGrant(grant),
    use_id,
    RemoteScope(scope),
    expected_path,
    verb,
    body,
    current,
  )
}

///|
// One durable credential claim/send Owner for both typed domains. Public
// Remote entrypoints keep their existing grant/scope/wire contract.
fn call_native_credential_resource_owned_scope(
  service : NativeCredentialResourceService,
  grant : NativeOwnedCredentialGrant,
  use_id : String,
  scope : NativeOwnedCredentialScope,
  expected_path : String?,
  verb : @http.NativeHttpMethod,
  body : Bytes,
  current : (() -> Bool)?,
) -> Result[NativeCredentialResponse, NativeCredentialResourceIssue] {
  guard owned_operation_for(service, scope) is Some(operation) &&
    operation.verb == verb &&
    body.length() <= operation.max_request_bytes else {
    return Err(AccessDenied)
  }
  let preparation_file = preparation_installation_for(service, scope)
  if scope is PreparationScope(_) {
    if preparation_file is None {
      return Err(AccessDenied)
    }
  }
  // Isolate the bytes from caller mutation during authorization callbacks.
  let saved_body = Bytes::from_array(body.to_array())
  if !owned_request_matches_scope(scope, verb, operation.path, saved_body) {
    return Err(AccessDenied)
  }
  let request : NativeCredentialRequest = {
    verb,
    path: operation.path,
    body: saved_body,
  }
  if expected_path is Some(path) {
    guard owned_operation_for(service, scope) is Some(operation) &&
      path == operation.path else {
      return Err(AccessDenied)
    }
  }
  let trusted_now_ms = match observe_trusted_clock(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let grant_cid = owned_credential_grant_cid(grant)
  let revoked = match native_credential_grant_revoked(service, grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard !revoked &&
    owned_operation_for(service, scope) is Some(operation) &&
    owned_grant_matches_scope(grant, scope) is Some((max_uses, expires_at)) &&
    !use_id.is_empty() &&
    use_id.length() <= 256 &&
    trusted_now_ms >= 0L &&
    trusted_now_ms < expires_at else {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  if !authorize_owned_credential(service, scope, {
      stage: "claim",
      grant_cid,
      use_cid: None,
      request: Some({
        ..request,
        body: Bytes::from_array(saved_body.to_array()),
      }),
    }) {
    return Err(AccessDenied)
  }
  if current is Some(check) && !check() {
    return Err(AccessDenied)
  }
  // The preparation profile has no unretained-response fallback. This check
  // follows current authorization but precedes ordinal claim and physical I/O.
  if scope is PreparationScope(_) && service.preparation_raw_store is None {
    return Err(InvalidConfiguration)
  }
  // A missing credential record is only an observation. The installed original
  // Journal claim must independently prove initial eligibility before a new
  // ordinal/use can be selected. Neither a replacement DB nor a lost claim
  // reply can manufacture that proof. Existing uses take the original retained
  // ordinal path below without claiming the initial responsibility again.
  if service.claim_initial_remote_use is Some(claim) &&
    grant is RemoteGrant(original_grant) &&
    scope is RemoteScope(original_scope) {
    match read_owned_credential_use(service, grant, use_id) {
      Ok(_) => ()
      Err(Journal(@sqlite.NotFound)) => {
        match claim(original_grant, use_id, original_scope) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        // The callback can persist a claim, lose current permission or outlive
        // the grant. Keep its original responsibility but consume no Resource
        // ordinal after a refused current authorization/lifetime/revocation.
        if !authorize_owned_credential(service, scope, {
            stage: "claim",
            grant_cid,
            use_cid: None,
            request: Some({
              ..request,
              body: Bytes::from_array(saved_body.to_array()),
            }),
          }) {
          return Err(AccessDenied)
        }
        let final_claim_time = match observe_trusted_clock(service) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if current is Some(check) && !check() {
          return Err(AccessDenied)
        }
        let claim_revoked = match
          native_credential_grant_revoked(service, grant_cid) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if claim_revoked || final_claim_time >= expires_at {
          return Err(Credential(@credential.CredentialGrantInactive))
        }
      }
      Err(issue) => return Err(issue)
    }
  }
  let ordinal = match
    service.database.claim_ordinal_action(
      use_scope(grant_cid),
      use_id,
      max_uses.to_int64(),
    ) {
    Ok(@sqlite.Retained(original_ordinal)) => {
      // Verify the retained original without constructing a replacement use.
      // Missing/corrupt custody is a typed refusal, never a fresh send right.
      let original_use = match
        read_owned_credential_use(service, grant, use_id) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if !owned_credential_use_matches_ordinal(original_use, original_ordinal) {
        return Err(Journal(@sqlite.Collision))
      }
      return Err(UseAlreadyClaimed)
    }
    Ok(@sqlite.Fresh(value)) if value <= 2147483647L => value.to_int()
    Ok(_) => return Err(InvalidConfiguration)
    Err(issue) => return Err(Journal(issue))
  }
  let credential_use = match
    prepare_owned_credential_use(
      grant,
      use_id,
      trusted_now_ms,
      ordinal - 1,
      revoked,
      scope,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  let use_cid = owned_credential_use_cid(credential_use)
  let use_body = match owned_credential_use_json(credential_use) {
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
  let raw_custody = match
    prepare_original_raw_custody(service, grant, credential_use) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if raw_custody is Some(custody) {
    match custody.reserve() {
      Ok(_) => ()
      Err(issue) => return Err(RawObservation(issue))
    }
  }
  // The actual use is already durable. Retain it in the installed original
  // custody before the final authorization/clock/revocation fences and I/O.
  // Unconfirmed retention leaves the claimed use unresolved, not failed/sent.
  match
    retain_remote_use_before_send(credential_use, service.retain_remote_use) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let send_time = match observe_trusted_clock(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if send_time >= expires_at {
    match persist_outcome(service, grant_cid, use_id, "failed", None) {
      Ok(_) => return Err(Credential(@credential.CredentialGrantInactive))
      Err(Journal(issue)) => return Err(TerminalRecordFailed("failed", issue))
      Err(issue) => return Err(issue)
    }
  }
  let authorized_by_host = authorize_owned_credential(service, scope, {
    stage: "send",
    grant_cid,
    use_cid: Some(use_cid),
    request: Some({ ..request, body: Bytes::from_array(saved_body.to_array()), }),
  })
  // The authorization callback may revoke a grant or take time. Re-read the
  // durable revocation and trusted lifetime after it, immediately before I/O.
  let current_send_time = match observe_trusted_clock(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The caller's guard may observe a Run cancellation or reviewer revocation
  // caused by an installed Host callback. No callback follows this final guard.
  let current_by_caller = match current {
    Some(check) => check()
    None => true
  }
  // The guard itself may revoke the credential. Read durable revocation after
  // all callbacks rather than trusting the earlier pre-claim observation.
  let send_revoked = match native_credential_grant_revoked(service, grant_cid) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if send_revoked || current_send_time >= expires_at {
    match persist_outcome(service, grant_cid, use_id, "failed", None) {
      Ok(_) => return Err(Credential(@credential.CredentialGrantInactive))
      Err(Journal(issue)) => return Err(TerminalRecordFailed("failed", issue))
      Err(issue) => return Err(issue)
    }
  }
  let authorized = authorized_by_host &&
    current_by_caller &&
    authorize_owned_credential_use(
      credential_use, current_send_time, send_revoked, scope,
    )
    is Ok(_)
  if !authorized {
    match persist_outcome(service, grant_cid, use_id, "failed", None) {
      Ok(_) => return Err(AccessDenied)
      Err(Journal(issue)) => return Err(TerminalRecordFailed("failed", issue))
      Err(issue) => return Err(issue)
    }
  }
  let transport = match preparation_file {
    Some(original) =>
      service.client.get_local_preparation(
        operation.resource_origin + operation.path,
        original,
        expires_at,
      )
    None =>
      service.client.request_bearer_file(
        verb,
        operation.resource_origin + operation.path,
        if verb == @http.Get {
          [{ name: "accept", value: "application/json", }]
        } else {
          [
            { name: "accept", value: "application/json", },
            { name: "content-type", value: "application/json", },
          ]
        },
        saved_body,
        operation.secret_path,
        expires_at,
      )
  }
  let response = match transport {
    Ok(value) => value
    Err(issue) =>
      match persist_outcome(service, grant_cid, use_id, "unknown", None) {
        Ok(_) => return Err(Transport(issue))
        Err(Journal(journal_issue)) =>
          return Err(TerminalRecordFailed("unknown", journal_issue))
        Err(other) => return Err(other)
      }
  }
  if raw_custody is Some(custody) {
    // Even non2xx and unadmitted Catalog bytes are retained before terminal
    // outcome/ACK. A save or readback failure keeps this original use claimed;
    // subsequent entry cannot allocate another ordinal or repeat the GET.
    match custody.persist(response.status, response.body) {
      Ok(_) => ()
      Err(issue) => return Err(RawObservation(issue))
    }
    match custody.confirm() {
      Ok(original) if original.use_cid == use_cid &&
        original.status == response.status &&
        original.body == response.body => ()
      Ok(_) => return Err(RawObservation(@publication.StateCollision))
      Err(issue) => return Err(RawObservation(issue))
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
      Ok(_) => {
        if raw_custody is Some(_) {
          match
            authorize_original_raw_return(
              service, grant, credential_use, scope, current,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
          }
        }
        return if verb == @http.Get {
          Err(ResourceRejected(response.status))
        } else {
          // Preserve the exact rejection response for the Effect Ledger.
          // HTTP rejection is not itself a semantic Effect outcome.
          Ok({ use_cid, status: response.status, body: response.body, })
        }
      }
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
  if raw_custody is Some(_) {
    match
      authorize_original_raw_return(
        service, grant, credential_use, scope, current,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
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
  query_native_owned_credential_use(
    service,
    RemoteGrant(grant),
    use_id,
    RemoteScope(scope),
  )
}

///|
fn query_native_owned_credential_use(
  service : NativeCredentialResourceService,
  grant : NativeOwnedCredentialGrant,
  use_id : String,
  scope : NativeOwnedCredentialScope,
) -> Result[NativeCredentialUseStatus, NativeCredentialResourceIssue] {
  guard owned_operation_for(service, scope) is Some(_) &&
    owned_grant_matches_scope(grant, scope) is Some(_) &&
    !use_id.is_empty() &&
    use_id.length() <= 256 else {
    return Err(Credential(@credential.CredentialGrantInactive))
  }
  let grant_cid = owned_credential_grant_cid(grant)
  if !authorize_owned_credential(service, scope, {
      stage: "query",
      grant_cid,
      use_cid: None,
      request: None,
    }) {
    return Err(AccessDenied)
  }
  let admitted_use = match read_owned_credential_use(service, grant, use_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let use_cid = owned_credential_use_cid(admitted_use)
  if !authorize_owned_credential(service, scope, {
      stage: "return",
      grant_cid,
      use_cid: Some(use_cid),
      request: None,
    }) {
    return Err(AccessDenied)
  }
  read_credential_use_outcome(service.database, grant_cid, use_id, use_cid)
}

///|
// The existing outcome reader is shared by transport-backed query and
// original raw recovery. Absence preserves claimed; it never proves unsent.
fn read_credential_use_outcome(
  database : @sqlite.Database,
  grant_cid : String,
  use_id : String,
  use_cid : String,
) -> Result[NativeCredentialUseStatus, NativeCredentialResourceIssue] {
  let outcome = match database.read(outcome_scope(grant_cid), use_id) {
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

///|
// Exact original use readmission shared by retained-claim refusal and query.
// This performs no claim, record repair, outcome inference or Provider I/O.
fn read_owned_credential_use(
  service : NativeCredentialResourceService,
  grant : NativeOwnedCredentialGrant,
  use_id : String,
) -> Result[NativeOwnedCredentialUse, NativeCredentialResourceIssue] {
  read_owned_credential_use_record(service.database, grant, use_id)
}

///|
fn read_owned_credential_use_record(
  database : @sqlite.Database,
  grant : NativeOwnedCredentialGrant,
  use_id : String,
) -> Result[NativeOwnedCredentialUse, NativeCredentialResourceIssue] {
  let grant_cid = owned_credential_grant_cid(grant)
  let use_record = match database.read(use_scope(grant_cid), use_id) {
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
    admit_owned_credential_use(grant, use_json, use_cid) {
    Ok(value) => value
    Err(issue) => return Err(Credential(issue))
  }
  if owned_credential_use_id(admitted_use) != use_id {
    return Err(Journal(@sqlite.Collision))
  }
  Ok(admitted_use)
}
