///|
pub(all) enum NativeLocalSigningHistoryIssue {
  HistoryUnavailable
  HistoryOriginal(NativeClientRunJournalIssue)
  HistoryKey(NativeLocalSigningOriginalIssue)
  HistoryCredential(@credential_resource.NativeCredentialResourceIssue)
}

///|
// Current original Client RunRead and independent selected Reviewer/key are
// deliberately separate from issuer issue, grant expiry and Resolution entry.
fn NativeLocalSigningKeyOriginal::require_signing_history_current(
  self : NativeLocalSigningKeyOriginal,
  authority : NativeLocalPolicyAuthority,
  request : @host.ClientRequestIdentity,
) -> Result[Unit, NativeLocalSigningHistoryIssue] {
  let (_, purpose, _, _, _, _, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    self.account.selection,
  )
  if purpose != @credential.ReviewerProof ||
    self.account.kind != @checkpoint.EffectSet ||
    !physical_equal(authority.host, self.account.host) ||
    !(authority.purpose is ReadRunMaterials) {
    return Err(HistoryUnavailable)
  }
  if !authority.current_for(self.account.host.journal, request) {
    return Err(HistoryOriginal(AuthorizationDenied))
  }
  match self.require_current_key() {
    Ok(_) => ()
    Err(issue) => return Err(HistoryKey(issue))
  }
  if !authority.current_for(self.account.host.journal, request) {
    return Err(HistoryOriginal(AuthorizationDenied))
  }
  // No caller callback follows this original Root/file lifetime observation.
  // A last Host/account read cannot silently replace this adopted generation.
  match self.projection.export_original() {
    Ok(bytes) if bytes == self.exported => Ok(())
    Ok(_) | Err(_) => Err(HistoryKey(SigningOriginalUnavailable))
  }
}

///|
// Only this read operation extracts a retained Signing original without a
// caller-provided replacement grant. The full existing custody scan and the
// original operation/request/Run/key/issuer joins remain in the same journal TX.
fn NativeLocalSigningKeyOriginal::read_signing_history_locked(
  self : NativeLocalSigningKeyOriginal,
  authority : NativeLocalPolicyAuthority,
  request : @host.ClientRequestIdentity,
  operation_id : String,
  use_id : String,
) -> Result[
  @credential_resource.NativeLocalSigningHistoryCandidate,
  NativeLocalSigningHistoryIssue,
] {
  let host = self.account.host
  if !authority.current_for(host.journal, request) ||
    self.account.require_current_account() is Err(_) {
    return Err(HistoryOriginal(AuthorizationDenied))
  }
  match host.local_grant_custody(self.account.crypto) {
    Ok(_) => ()
    Err(issue) => return Err(HistoryOriginal(issue))
  }
  let key = match
    local_grant_original_key(self.account.crypto, request, operation_id) {
    Ok(value) => value
    Err(issue) => return Err(HistoryOriginal(issue))
  }
  let row : @sqlite.NativeJournalEntry = match
    host.database.read("client_local_grant_originals", key) {
    Ok(value) => { key, body: value.body, revision: value.revision, }
    Err(@sqlite.NotFound) => return Err(HistoryUnavailable)
    Err(issue) => return Err(HistoryOriginal(Physical(issue)))
  }
  let original = match read_local_grant_original(self.account.crypto, row) {
    Ok(value) => value
    Err(issue) => return Err(HistoryOriginal(issue))
  }
  if original.operation_id != operation_id ||
    @host.client_request_identity_relation(original.request, request) !=
    @host.SameRequest {
    return Err(HistoryOriginal(ChangedIntent))
  }
  guard original.grant is SigningGrant(grant) else {
    return Err(HistoryUnavailable)
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  // Pure correspondence with the same opaque selected key, never an authority
  // minted from public CID/filename equality. The current key is checked on
  // both sides outside this TX; the existing locked reader restores its exact
  // authenticated private projection during the all-original custody scan.
  if scope.purpose != @credential.ReviewerProof ||
    scope.account_configuration_cid != self.account.account_configuration_cid ||
    scope.account_id != self.account.account_id ||
    scope.authority_scope_cid != self.account.scope ||
    scope.host_adoption_cid != host.adoption_cid ||
    scope.key_configuration_cid != self.account.file.content_cid ||
    scope.key_generation_cid != self.generation_cid ||
    scope.key_public_key_cid != self.public_key.cid() ||
    scope.checkpoint_kind != self.account.kind {
    return Err(HistoryUnavailable)
  }
  match
    @credential_resource.prepare_native_local_signing_history_candidate(
      host.database,
      grant,
      use_id,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(HistoryCredential(issue))
  }
}

///|
/// Read only the already saved claim/use/outcome for an explicit original
/// Signing operation. The current original Client needs RunRead; the selected
/// Reviewer independently needs resolve and authenticated original key custody.
/// Issuer installation/configuration joins remain authentic, but issuer issue
/// and a new credential/issuer read tuple are not used as read permission.
///
/// No clock, new ordinal, private key body, signer, issuer, repair, expiry
/// renewal or Resolution admission is invoked. Missing/Unknown history is not
/// unsent. Succeeded outcome metadata does not return an exact signature.
pub fn NativeLocalSigningKeyOriginal::lookup_signing_history(
  self : NativeLocalSigningKeyOriginal,
  principal : String,
  connection : String,
  request : @host.ClientRequestIdentity,
  operation_id : String,
  use_id : String,
) -> Result[
  @credential_resource.NativeLocalSigningHistoryCandidate,
  NativeLocalSigningHistoryIssue,
] {
  let host = self.account.host
  let authority = match
    native_local_policy_authority_for(
      host,
      self.account.crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(HistoryOriginal(issue))
  }
  match self.require_signing_history_current(authority, request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let mut read_issue : NativeLocalSigningHistoryIssue? = None
  let result = host.journal.transaction(() => {
    match
      self.read_signing_history_locked(authority, request, operation_id, use_id) {
      Ok(value) => Ok(value)
      Err(issue) => {
        read_issue = Some(issue)
        // Existing custody checks intentionally roll back any tentative
        // reservation on failure. Never commit a missing original's repair.
        Err(AuthorizationDenied)
      }
    }
  })
  // Re-evaluate actual current even after missing/foreign/malformed history.
  // The lower storage candidate cannot turn its own success into permission.
  let after = self.require_signing_history_current(authority, request)
  // Lost commit/rollback ACK retains the same original Unknown responsibility.
  // A resulting current denial must not turn it into a known read refusal.
  if result is Err(TransactionUnknown) {
    return Err(HistoryOriginal(TransactionUnknown))
  }
  match after {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match result {
    Err(issue) => Err(read_issue.unwrap_or(HistoryOriginal(issue)))
    Ok(value) => Ok(value)
  }
}
