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
  resolution_proof? : @checkpoint.PreparedResolutionProof? = None,
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
  match
    host.local_grant_custody(
      host.epoch.crypto,
      capture=key.original.original_read.map(value => value.0),
    ) {
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
      if metadata.earlier_valid_until != earlier_valid_until ||
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
      resolution_proof~,
      capture=key.original.original_read.map(value => value.0),
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
