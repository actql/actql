///|
// Historical issuer/key correspondence in the same Journal TX, not Account
// authority or a signing permit. ReviewerProof retains its separate validator.
fn NativeLocalHostConnection::check_initial_host_attestation_grant_original_locked(
  self : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  expected_run : String,
  capture? : NativeLocalJournalCapture? = None,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard original.grant is SigningGrant(grant) &&
    original.initial_issue is Some(_) else {
    return Err(CustodyLost)
  }
  match
    self.check_signing_grant_submission_locked(
      grant,
      original.request,
      expected_run,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  let control = match
    self.database.read("client_local_installation_custody", "host") {
    Ok(value) if value.revision == 0L => value
    _ => return Err(CustodyLost)
  }
  let fields = match
    read_local_initial_host_signing_control(self, control.body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let reviewer = match read_local_initial_signing_control(self, control.body) {
    Ok(Some(value)) => value
    _ => return Err(CustodyLost)
  }
  let metadata = match
    read_local_initial_signing_issue_record(self, original, fields) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard scope.purpose == @credential.HostAttestation &&
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
    file.content_cid == metadata.host_configuration_cid &&
    self.selected_configuration(file.name) is Ok(body) &&
    body == file.body &&
    initial_reviewer_host_configuration(body) else {
    return Err(CustodyLost)
  }
  // Compare actual raw keys and file identities. The Reviewer separation
  // reader already checks its paired Host and configured generations; passing
  // Host fields to that Reviewer-only check would compare the Host to itself.
  guard fields.public_key.raw32() is Ok(host_key) &&
    reviewer.public_key.raw32() is Ok(reviewer_key) &&
    host_key != reviewer_key &&
    fields.exported.length() > 106 &&
    reviewer.exported.length() > 106 &&
    fields.exported[26:42].to_owned() != reviewer.exported[26:42].to_owned() else {
    return Err(CustodyLost)
  }
  if self.require_initial_signing_separation(reviewer) is Err(_) ||
    self.session.root.restore_private_file_projection(fields.exported) is Err(_) {
    return Err(CustodyLost)
  }
  self.check_binding().map_err(_ => CustodyLost)
}

///|
fn local_initial_host_prepared_key(
  original : NativeLocalGrantOriginal,
) -> String {
  // A private storage discriminator, not a new identity domain or grant key.
  original.operation_cid + "/host-prepared"
}

///|
// Validate exact canonical body/time correspondence only. The original Core
// admission and actual current role gate remain the enclosing caller's duty.
fn local_initial_host_prepared_body(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
  wire : String,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  guard original.grant is SigningGrant(grant) &&
    original.initial_issue is Some(_) else {
    return Err(CustodyLost)
  }
  let scope = @credential.local_signing_credential_grant_scope(grant)
  if scope.purpose != @credential.HostAttestation {
    return Err(ChangedIntent)
  }
  let body = @utf8.encode(wire)
  if body.length() > 65536 {
    return Err(CapacityExceeded)
  }
  let control = match
    host.database.read("client_local_installation_custody", "host") {
    Ok(value) if value.revision == 0L => value
    _ => return Err(CustodyLost)
  }
  let fields = match
    read_local_initial_host_signing_control(host, control.body) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let metadata = match
    read_local_initial_signing_issue_record(host, original, fields) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let limits = native_checkpoint_limits()
  let node = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_wire_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  try {
    let value = @canonical.from_source(
      node,
      limits.max_nodes,
      limits.max_depth,
      limits.max_wire_bytes,
      data_keys=true,
    )
    guard @canonical.object_field(value, "verified_at")
      is Some(String(verified_at)) &&
      @values.epoch_milliseconds_timestamp(metadata.sampled_at) ==
      Some(verified_at) &&
      @canonical.stringify_value(
        value,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) ==
      wire &&
      local_adoption_digest(host.epoch.crypto, body) is Ok(digest) &&
      digest == scope.preimage else {
      return Err(CustodyLost)
    }
    Ok(body)
  } catch {
    _ => Err(CustodyLost)
  }
}

///|
fn local_initial_host_prepared_locked(
  host : NativeLocalHostConnection,
  original : NativeLocalGrantOriginal,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  if !host.journal.transaction_active || host.journal.fenced {
    return Err(Fenced)
  }
  let row = match
    host.database.read(
      "client_local_signing_candidate_originals",
      local_initial_host_prepared_key(original),
    ) {
    Ok(value) if value.revision == 0L && value.body.length() <= 65536 => value
    _ => return Err(CustodyLost)
  }
  let wire = @utf8.decode(row.body) catch { _ => return Err(CustodyLost) }
  local_initial_host_prepared_body(host, original, wire)
}
