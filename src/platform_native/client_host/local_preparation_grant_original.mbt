///|
// Trusted checked-request/credential installation assembly remains required
// before this private storage seam is exposed through the CLI. It stores an
// explicitly authorized original, never an automatic read or mutation grant.
fn local_preparation_grant_original(
  crypto : @crypto.Library,
  operation_id : String,
  request : @host.ClientRequestIdentity,
  issuer_selection_cid : String,
  grant : @credential.LocalPreparationCredentialGrant,
) -> Result[NativeLocalGrantOriginal, NativeClientRunJournalIssue] {
  local_owned_grant_original(
    crypto,
    operation_id,
    request,
    issuer_selection_cid,
    PreparationGrant(grant),
  )
}

///|
fn NativeLocalCredentialIssuerBinding::check_preparation_original_locked(
  self : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
  fence : NativeClientEffectPreparationFence,
) -> Result[Unit, NativeClientRunJournalIssue] {
  if self.require_current(self.host, original.operation_cid) is Err(_) {
    return Err(AuthorizationDenied)
  }
  guard original.grant is PreparationGrant(grant) &&
    physical_equal(fence.work.journal, self.host.journal) &&
    @host.client_request_identity_relation(original.request, fence.work.request)
    is @host.SameRequest else {
    return Err(ForeignRun)
  }
  // Reuse the existing locked read projection for callbacks inside this
  // transaction. Nested journal writes remain forbidden; original lookup reads
  // the same locked record. Always restore the flag before returning a Result.
  self.host.journal.publication_read_locked = true
  let operational = fence.require_current()
  self.host.journal.publication_read_locked = false
  if operational is Err(_) {
    return Err(AuthorizationDenied)
  }
  let scope = @credential.local_preparation_credential_grant_scope(grant)
  if scope.preparation_fence != fence.identity ||
    scope.host_adoption_cid != self.host.adoption_cid ||
    scope.authority_scope_cid != self.scope ||
    scope.submission_scope_cid !=
    @host.client_request_scope_cid(original.request) ||
    scope.account_configuration_cid !=
    self.host.session.configuration.configuration_cid() ||
    scope.account_id != self.host.session.configuration.account_id() ||
    scope.principal != self.principal ||
    original.issuer_selection_cid != self.file.content_cid ||
    !local_original_grant_matches_issuer(original.grant, self.selection) {
    return Err(AuthorizationDenied)
  }
  // Current issuer acquisition can outlive an earlier read of this Run. Check
  // exact original started/cancelled/Checkpoint facts again, under this lock.
  guard self.host.journal.retained(original.request) is Ok(Some(record)) &&
    record.physical_start_claimed &&
    !record.cancellation_requested &&
    record.checkpoint is None &&
    record.revision >= fence.work.first_start.observed_revision &&
    @publication.publication_contract_identity(record.definition) ==
    fence.work.first_start.definition_cid else {
    return Err(Checkpoint(NeedsOriginalContinuation))
  }
  self
  .require_current(self.host, original.operation_cid)
  .map_err(_ => AuthorizationDenied)
}

///|
fn NativeLocalCredentialIssuerBinding::retain_preparation_grant_original(
  self : NativeLocalCredentialIssuerBinding,
  original : NativeLocalGrantOriginal,
  fence : NativeClientEffectPreparationFence,
) -> Result[Unit, NativeClientRunJournalIssue] {
  // The opaque operational token is acquired outside this storage transaction;
  // bytes read from custody never mint a replacement Work or token on recovery.
  if fence.require_current() is Err(_) {
    return Err(AuthorizationDenied)
  }
  self.host.journal.transaction(() => {
    match self.check_preparation_original_locked(original, fence) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    guard local_owned_grant_original(
        self.crypto,
        original.operation_id,
        original.request,
        original.issuer_selection_cid,
        original.grant,
      )
      is Ok(exact) &&
      exact.operation_cid == original.operation_cid &&
      exact.intent == original.intent else {
      return Err(ChangedIntent)
    }
    self.append_grant_original_locked(original, () => {
      self.check_preparation_original_locked(original, fence)
    })
  })
}
