///|
// Default-only authenticated metadata in the existing immutable grant packet.
// A packet is not issuer authority or a signing permit. Its only writer is the
// private first-issue storage phase of the same initial Host/key Owner.
priv struct NativeLocalInitialSigningIssueRecord {
  sampled_at : Int64
  earlier_valid_until : Int64?
  host_configuration_file : String
  host_configuration_cid : String
  connection : String
  signing_resource : String?
}

///|
fn initial_signing_issue_int64(text : String) -> Int64? {
  let value = @string.parse_int64(text) catch { _ => return None }
  if value < 0L || value.to_string() != text {
    None
  } else {
    Some(value)
  }
}

///|
fn local_initial_signing_issue_payload(
  original : NativeLocalGrantOriginal,
  initialization_intent : String,
  policy_cid : String,
  record : NativeLocalInitialSigningIssueRecord,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  let fields = [
    ("connection", record.connection),
    (
      "earlier_valid_until",
      record.earlier_valid_until.map(value => value.to_string()).unwrap_or(""),
    ),
    ("grant_cid", local_original_grant_cid(original.grant)),
    ("host_configuration_cid", record.host_configuration_cid),
    ("host_configuration_file", record.host_configuration_file),
    ("initialization_intent_cid", initialization_intent),
    ("operation_cid", original.operation_cid),
    ("policy_cid", policy_cid),
    ("sampled_at", record.sampled_at.to_string()),
    ("version", "actql-native-local-installation-original/0.1"),
  ]
  if record.signing_resource is Some(resource) {
    fields.push(("signing_resource", resource))
  }
  local_adoption_record(fields).map_err(_ => Encoding)
}

///|
// Pure original-record checks, not current permission. The actual initial
// control HMAC, Store generation and selected Host file are re-read below.
fn read_local_initial_signing_issue_record(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  fields : NativeLocalInitialSigningFields,
) -> Result[NativeLocalInitialSigningIssueRecord, NativeClientRunJournalIssue] {
  guard original.grant is SigningGrant(grant) &&
    original.initial_issue is Some(packet) else {
    return Err(CustodyLost)
  }
  let payload = match
    read_local_installation_authenticated_payload(host, packet) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let keys = [
    "connection", "earlier_valid_until", "grant_cid", "host_configuration_cid", "host_configuration_file",
    "initialization_intent_cid", "operation_cid", "policy_cid", "sampled_at", "version",
  ]
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if scope.purpose == @credential.HostAttestation {
    keys.push("signing_resource")
  }
  let values = match local_adoption_fields(payload, keys) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let signing_resource = if scope.purpose == @credential.HostAttestation {
    let resource = values[10]
    if resource.is_empty() ||
      resource.length() > 256 ||
      resource.contains("\u{0}") {
      return Err(CustodyLost)
    }
    Some(resource)
  } else {
    None
  }
  guard initial_signing_issue_int64(values[8]) is Some(sampled_at) else {
    return Err(CustodyLost)
  }
  let earlier_valid_until = if values[1] == "" {
    None
  } else {
    guard initial_signing_issue_int64(values[1]) is Some(bound) else {
      return Err(CustodyLost)
    }
    Some(bound)
  }
  if values[2] != local_original_grant_cid(original.grant) ||
    values[5] != host.session.intent_cid ||
    values[6] != original.operation_cid ||
    values[7] != fields.policy.cid() ||
    values[9] != "actql-native-local-installation-original/0.1" {
    return Err(CustodyLost)
  }
  let issue = match
    fields.policy.prepare_first_issue(sampled_at, earlier_valid_until) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let expected = match
    @credential.prepare_local_signing_credential_grant(
      fields.issuer,
      scope,
      issue.expires_at(),
      fields.policy.max_uses(),
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if @credential.local_signing_credential_grant_cid(expected) !=
    @credential.local_signing_credential_grant_cid(grant) {
    return Err(CustodyLost)
  }
  Ok({
    sampled_at,
    earlier_valid_until,
    host_configuration_file: values[4],
    host_configuration_cid: values[3],
    connection: values[0],
    signing_resource,
  })
}

///|
// Already in the original Journal TX. Never call the public restore reader
// (which owns its own TX), sample a clock, read a secret or backfill an original.
fn NativeLocalHostConnection::check_initial_signing_grant_original_locked(
  self : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  expected_run : String,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard original.grant is SigningGrant(grant) else { return Err(CustodyLost) }
  match
    self.check_signing_grant_submission_locked(
      grant,
      original.request,
      expected_run,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if scope.purpose == @credential.HostAttestation {
    return self.check_initial_host_attestation_grant_after_submission_locked(
      original,
      capture~,
    )
  }
  let control = match
    self.database.read("client_local_installation_custody", "host") {
    Ok(value) if value.revision == 0L => value
    _ => return Err(CustodyLost)
  }
  guard read_local_initial_signing_control(self, control.body)
    is Ok(Some(fields)) else {
    return Err(CustodyLost)
  }
  let metadata = match
    read_local_initial_signing_issue_record(self, original, fields) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard scope.purpose == @credential.ReviewerProof &&
    scope.checkpoint_kind == @checkpoint.EffectSet &&
    local_adoption_digest(self.epoch.crypto, control.body) is Ok(configuration) &&
    configuration == scope.key_configuration_cid &&
    original.issuer_selection_cid == configuration &&
    local_adoption_digest(self.epoch.crypto, fields.exported) is Ok(generation) &&
    generation == scope.key_generation_cid &&
    scope.key_public_key_cid == fields.public_key.cid() &&
    scope.key_id == fields.public_key.cid() &&
    self.session.configuration.configuration_cid() ==
    scope.account_configuration_cid &&
    self.session.configuration.account_id() == scope.account_id &&
    self.adoption_cid == scope.host_adoption_cid &&
    self.authority_scope_cid(
      scope.principal,
      metadata.connection,
      self.epoch.crypto,
      capture~,
    )
    is Ok(authority) &&
    authority == scope.authority_scope_cid else {
    return Err(CustodyLost)
  }
  guard self.session.settings.files
    .iter()
    .find_first(file => file.name == metadata.host_configuration_file)
    is Some(file) &&
    file.content_cid == metadata.host_configuration_cid else {
    return Err(CustodyLost)
  }
  // The scope check above already joined this SAME Host/Library/Read. Select
  // its admitted bytes without another full Source/package walk; the final
  // physical/current fence after key-generation checks remains below.
  let body = match capture {
    Some(owner) => owner.selected_configuration_in_original_read(file.name)
    None => self.selected_configuration(file.name)
  }
  guard body is Ok(body) &&
    body == file.body &&
    initial_reviewer_host_configuration(body) else {
    return Err(CustodyLost)
  }
  if self.require_initial_signing_separation(fields) is Err(_) ||
    self.session.root.restore_private_file_projection(fields.exported) is Err(_) {
    return Err(CustodyLost)
  }
  self.check_binding().map_err(_ => CustodyLost)
}

///|
// Storage preparation only. The enclosing trusted original operation must
// separately check current RunRead/Reviewer, its paired subject/Checkpoint and
// cancellation before/after this phase and confirm the same TX. Caller times
// are private diagnostic inputs; a public caller must sample the actual clock.
fn local_initial_signing_grant_original_locked(
  key : NativeLocalInitialReviewerSigningKey,
  request : @host.ClientRequestIdentity,
  scope : @credential.LocalSigningCredentialScope,
  operation_id : String,
  sampled_at : Int64,
  earlier_valid_until : Int64?,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  let host = key.original.host
  if InitialReviewerKey(key).require_signing_key_scope(scope) is Err(_) {
    return Err(AuthorizationDenied)
  }
  let issue = match
    key.original.policy.prepare_first_issue(sampled_at, earlier_valid_until) {
    Ok(value) => value
    Err(_) => return Err(AuthorizationDenied)
  }
  let grant = match
    @credential.prepare_local_signing_credential_grant(
      key.original.issuer,
      scope,
      issue.expires_at(),
      key.original.policy.max_uses(),
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let original = match
    local_owned_grant_original(
      host.epoch.crypto,
      operation_id,
      request,
      key.fields.key_configuration_cid,
      SigningGrant(grant),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record : NativeLocalInitialSigningIssueRecord = {
    sampled_at,
    earlier_valid_until,
    host_configuration_file: key.installed.file,
    host_configuration_cid: match
      key.original.selected_configuration_cid_after_current(
        key.installed.file,
        key.installed.original_bytes,
      ) {
      Ok(value) => value
      Err(_) => return Err(Encoding)
    },
    connection: key.installed.reviewer.connection,
    signing_resource: None,
  }
  let payload = match
    local_initial_signing_issue_payload(
      original,
      host.session.intent_cid,
      key.original.policy.cid(),
      record,
    ) {
    Ok(value) if value.length() <= 2048 => value
    Ok(_) => return Err(CapacityExceeded)
    Err(issue) => return Err(issue)
  }
  let packet = match
    local_installation_packet_in_transaction(
      host.database,
      host.epoch.crypto,
      payload,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let authenticated = { ..original, initial_issue: Some(packet), }
  match
    host.check_initial_signing_grant_original_locked(
      authenticated,
      scope.run_definition_cid,
      capture=key.original.original_read.map(value => value.0),
    ) {
    Ok(_) => Ok(authenticated)
    Err(issue) => Err(issue)
  }
}
