///|
// Identity checks only. The Signing subject's authenticated Submission identity
// is distinct from its logical request scope and from both signer/issuer scopes.
fn local_signing_grant_matches_request(
  grant : @credential.LocalSigningCredentialGrant,
  request : @host.ClientRequestIdentity,
) -> Bool {
  let scope = @credential.local_signing_credential_grant_scope(grant)
  scope.request_cid == @host.client_request_intent_cid(request) &&
  scope.request_scope_cid == @host.client_request_scope_cid(request) &&
  scope.submission_scope_cid == @host.client_request_caller_id(request)
}

///|
// Existing storage accounting remains per logical request. It does not rename
// the public Signing Submission identity or grant permission from a filename.
fn local_original_grant_reservation_scope(
  original : NativeLocalGrantOriginal,
) -> String {
  match original.grant {
    SigningGrant(_) => @host.client_request_scope_cid(original.request)
    _ => local_original_grant_facts(original.grant).submission_scope_cid
  }
}

///|
// Called inside the original journal transaction. Authenticate the original
// Submission/Run join through the existing decoder/epoch Owner, without
// turning its integrity result into a read, signing or new-start permission.
fn NativeLocalHostConnection::check_signing_grant_original_locked(
  self : NativeLocalHostConnection,
  grant : @credential.LocalSigningCredentialGrant,
  request : @host.ClientRequestIdentity,
  expected_run : String,
) -> Result[Unit, NativeClientRunJournalIssue] {
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if !local_signing_grant_matches_request(grant, request) ||
    scope.run_definition_cid != expected_run {
    return Err(CustodyLost)
  }
  // Keep this decoded Submission in its own phase; no large Run record escapes
  // alongside the later key/projection reads.
  let reference = {
    let row = match
      self.database.read("client_submitted_intents", scope.submission_scope_cid) {
      Ok(value) => value
      Err(issue) => return Err(Physical(issue))
    }
    let decoded = match
      self.journal.inspect_submitted_intent_row({
        key: scope.submission_scope_cid,
        body: row.body,
        revision: row.revision,
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard decoded.run_admission is Some(admission) &&
      @host.client_request_identity_relation(admission.0, request)
      is @host.SameRequest &&
      admission.1 == expected_run else {
      return Err(CustodyLost)
    }
    native_submission_reference_record(decoded.reference)
  }
  // Only original epoch authentication is consumed here. Current read/purpose
  // authority is independently required by the eventual history endpoint.
  match
    self.journal.verify_submission_locked(
      self.epoch,
      reference,
      @host.client_request_authority_scope_cid(request),
      true,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let key_file = match
    self.session.settings.files
    .iter()
    .find_first(file => file.content_cid == scope.key_configuration_cid) {
    Some(value) => value
    None => return Err(CustodyLost)
  }
  let wire = @utf8.decode(key_file.body) catch { _ => return Err(CustodyLost) }
  let selected = match
    @credential_resource.admit_native_local_signing_key_selection(wire) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (_, purpose, principal, connection, _, key_id, _, _) = @credential_resource.native_local_signing_key_selection_projection(
    selected,
  )
  if purpose != scope.purpose ||
    principal != scope.principal ||
    key_id != scope.key_id ||
    !@credential_resource.native_local_signing_key_selection_allows_kind(
      selected,
      scope.checkpoint_kind,
    ) {
    return Err(CustodyLost)
  }
  guard self.authority_scope_cid(principal, connection, self.epoch.crypto)
    is Ok(current_scope) &&
    current_scope == scope.authority_scope_cid else {
    return Err(CustodyLost)
  }
  let row = match
    self.database.read("client_local_installation_originals", key_file.name) {
    Ok(value) if value.revision == 0L => value
    Ok(_) => return Err(CustodyLost)
    Err(issue) => return Err(Physical(issue))
  }
  let payload = match
    read_local_installation_authenticated_payload(self, row.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (projection, public_key) = match
    read_local_signing_installation_record(self, key_file, payload) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  guard public_key is Some(public_key) &&
    public_key.cid() == scope.key_public_key_cid &&
    local_adoption_digest(self.epoch.crypto, projection) is Ok(generation) &&
    generation == scope.key_generation_cid else {
    return Err(CustodyLost)
  }
  // Only current projection metadata is read, never secret key bytes. Missing
  // old originals cannot be backfilled from a fresh stat or current PEM.
  self.session.source_root
  .restore_private_file_projection(projection)
  .map(_ => ())
  .map_err(_ => CustodyLost)
}
