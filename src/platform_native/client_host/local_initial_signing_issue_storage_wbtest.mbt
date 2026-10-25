///|
// Private storage phases, never a reusable physical signing permit. The
// enclosing original operation owns the paired/current gates and same TX ACK.
priv enum NativeLocalInitialSigningStorageResult {
  InitialStorageClaim(
    NativeLocalGrantOriginal,
    @credential.LocalSigningCredentialUse
  )
  InitialStorageHistory(
    NativeLocalGrantOriginal,
    @credential_resource.NativeLocalSigningHistoryCandidate
  )
}

///|
priv enum NativeLocalInitialSigningStorageIssue {
  InitialStorageJournal(NativeClientRunJournalIssue)
  InitialStorageCredential(@credential_resource.NativeCredentialResourceIssue)
}

///|
fn local_initial_signing_issue_storage_locked(
  key : NativeLocalInitialReviewerSigningKey,
  request : @host.ClientRequestIdentity,
  scope : @credential.LocalSigningCredentialScope,
  operation_id : String,
  earlier_valid_until : Int64?,
  trusted_sample : () -> Int64,
  current : () -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[
  NativeLocalInitialSigningStorageResult,
  NativeLocalInitialSigningStorageIssue,
] {
  let host = key.original.host
  if !host.journal.transaction_active || host.journal.fenced {
    return Err(InitialStorageJournal(Fenced))
  }
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(InitialStorageJournal(issue))
  }
  match host.local_grant_custody(host.epoch.crypto) {
    Ok(_) => ()
    Err(issue) => return Err(InitialStorageJournal(issue))
  }
  let row_key = match
    local_grant_original_key(host.epoch.crypto, request, operation_id) {
    Ok(value) => value
    Err(issue) => return Err(InitialStorageJournal(issue))
  }
  // A retained operation is read before the clock callback. Missing use,
  // corruption, a foreign original or an uncertain earlier commit cannot
  // select a new sample/expiry, ordinal, claim, key or grant.
  match host.database.read("client_local_grant_originals", row_key) {
    Ok(row) => {
      let original = match
        read_local_grant_original(host.epoch.crypto, {
          key: row_key,
          body: row.body,
          revision: row.revision,
        }) {
        Ok(value) => value
        Err(issue) => return Err(InitialStorageJournal(issue))
      }
      guard original.grant is SigningGrant(grant) &&
        original.initial_issue is Some(_) &&
        original.operation_id == operation_id &&
        @host.client_request_identity_relation(original.request, request)
        is @host.SameRequest &&
        @credential.local_signing_credential_grant_scope(grant) == scope &&
        original.issuer_selection_cid == key.fields.key_configuration_cid else {
        return Err(InitialStorageJournal(ChangedIntent))
      }
      let fields : NativeLocalInitialSigningFields = {
        exported: key.original.exported,
        policy: key.original.policy,
        public_key: key.original.public_key,
        public_key_pem: key.original.public_key_pem,
        issuer: key.original.issuer,
      }
      let metadata = match
        read_local_initial_signing_issue_record(host, original, fields) {
        Ok(value) => value
        Err(issue) => return Err(InitialStorageJournal(issue))
      }
      if metadata._observed_earlier_valid_until != earlier_valid_until ||
        metadata.host_configuration_file != key.installed.file ||
        metadata.connection != key.installed.reviewer.connection {
        return Err(InitialStorageJournal(ChangedIntent))
      }
      let history = match
        @credential_resource.prepare_native_local_original_signing_history_candidate(
          host.database,
          grant,
        ) {
        Ok(value) => value
        Err(issue) => return Err(InitialStorageCredential(issue))
      }
      return match current() {
        Ok(_) => Ok(InitialStorageHistory(original, history))
        Err(issue) => Err(InitialStorageJournal(issue))
      }
    }
    Err(@sqlite.NotFound) => ()
    Err(issue) => return Err(InitialStorageJournal(Physical(issue)))
  }
  let sampled_at = trusted_sample()
  match current() {
    Ok(_) => ()
    Err(issue) => return Err(InitialStorageJournal(issue))
  }
  let original = match
    local_initial_signing_grant_original_locked(
      key, request, scope, operation_id, sampled_at, earlier_valid_until,
    ) {
    Ok(value) => value
    Err(issue) => return Err(InitialStorageJournal(issue))
  }
  match
    append_local_owned_grant_original_locked(
      host,
      host.epoch.crypto,
      original,
      current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(InitialStorageJournal(issue))
  }
  guard original.grant is SigningGrant(grant) else {
    return Err(InitialStorageJournal(CustodyLost))
  }
  let claimed = match
    @credential_resource.claim_native_local_original_signing_use_in_transaction(
      host.database,
      grant,
      scope,
      sampled_at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(InitialStorageCredential(issue))
  }
  match current() {
    Ok(_) => Ok(InitialStorageClaim(original, claimed))
    Err(issue) => Err(InitialStorageJournal(issue))
  }
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
    _observed_sampled_at: sampled_at,
    _observed_earlier_valid_until: earlier_valid_until,
    host_configuration_file: key.installed.file,
    host_configuration_cid: match
      local_adoption_digest(host.epoch.crypto, key.installed.original_bytes) {
      Ok(value) => value
      Err(_) => return Err(Encoding)
    },
    connection: key.installed.reviewer.connection,
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
    ) {
    Ok(_) => Ok(authenticated)
    Err(issue) => Err(issue)
  }
}

///|
fn local_initial_signing_issue_payload(
  original : NativeLocalGrantOriginal,
  initialization_intent : String,
  policy_cid : String,
  record : NativeLocalInitialSigningIssueRecord,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  local_adoption_record([
    ("connection", record.connection),
    (
      "earlier_valid_until",
      record._observed_earlier_valid_until
      .map(value => value.to_string())
      .unwrap_or(""),
    ),
    ("grant_cid", local_original_grant_cid(original.grant)),
    ("host_configuration_cid", record.host_configuration_cid),
    ("host_configuration_file", record.host_configuration_file),
    ("initialization_intent_cid", initialization_intent),
    ("operation_cid", original.operation_cid),
    ("policy_cid", policy_cid),
    ("sampled_at", record._observed_sampled_at.to_string()),
    ("version", "actql-native-local-installation-original/0.1"),
  ]).map_err(_ => Encoding)
}
