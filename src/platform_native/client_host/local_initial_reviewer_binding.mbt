///|
// The public Host file is an adopted physical original, not caller DATA or a
// project selector. Explicit signers (including an empty map) and any named
// selection cannot fall back to the initialized Store key.
fn initial_reviewer_host_configuration(wire : Bytes) -> Bool {
  let text = @utf8.decode(wire) catch { _ => return false }
  match
    @host.admit_client_host_signer_configuration(text, {
      max_wire_bytes: 65536,
      max_nodes: 1024,
      max_depth: 16,
      max_signers: 64,
    }) {
    Ok(configuration) => !configuration.has_explicit_signers()
    Err(_) => false
  }
}

///|
fn NativeLocalInstalledEffectReviewer::initial_reviewer_original_current(
  self : NativeLocalInstalledEffectReviewer,
  original : NativeLocalInitialSigningOriginal,
) -> Bool {
  // The sole caller just selected this Host's original configuration through
  // selected_configuration, which completed the full binding check. Only the
  // pure equality/reference comparisons below separate it from this entry.
  physical_equal(original.host, self.host) &&
  original.require_current_after_host_binding() is Ok(_) &&
  initial_reviewer_host_configuration(self.original_bytes) &&
  self.reviewer.key_id == original.public_key.cid() &&
  self.reviewer.public_key_pem == original.public_key_pem &&
  self.reviewer.reviewer_id == self.reviewer.principal
}

///|
/// Trusted Host assembly only: join the same initialized Store/key original,
/// actual actor selection and current independent run:resolve Account tuple.
/// The selected public Host configuration must already belong to this Host's
/// authenticated installation. No configured Reviewer file is fabricated and
/// no credential issue permission, grant, use or signature is created here.
pub fn NativeLocalHostConnection::install_initial_effect_reviewer(
  self : NativeLocalHostConnection,
  original : NativeLocalInitialSigningOriginal,
  principal : String,
  connection : String,
  host_configuration_file : String,
  signer_name? : String? = None,
) -> Result[
  NativeLocalInstalledEffectReviewer,
  NativeLocalEffectReviewerBindingIssue,
] {
  if signer_name is Some(_) ||
    !physical_equal(self, original.host) ||
    original.require_current() is Err(_) ||
    principal.is_empty() ||
    connection.is_empty() {
    return Err(ReviewerUnavailable)
  }
  let bytes = match original.selected_configuration(host_configuration_file) {
    Ok(value) => value
    Err(_) => return Err(ReviewerUnavailable)
  }
  if !initial_reviewer_host_configuration(bytes) {
    return Err(ReviewerUnavailable)
  }
  // Identity labels come from this actual initialization and actor. These
  // strings carry no registration or Allow without the original/current join.
  let installed : NativeLocalInstalledEffectReviewer = {
    host: self,
    file: host_configuration_file,
    original_bytes: bytes,
    reviewer: {
      enabled: true,
      principal,
      connection,
      key_id: original.public_key.cid(),
      reviewer_id: principal,
      public_key_pem: original.public_key_pem,
    },
    initial_original: Some(original),
  }
  if !installed.current() || original.require_current() is Err(_) {
    return Err(ReviewerUnavailable)
  }
  Ok(installed)
}

///|
/// Bind the initialized registration through the same original Checkpoint and
/// Client/Reviewer current checks as the configured route. No start/recapture
/// or legacy repair is performed. Signing still requires its exact original
/// preimage, private issuer admission and durable same-operation claim.
pub fn NativeLocalHostConnection::bind_initial_effect_reviewer(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  initial_original : NativeLocalInitialSigningOriginal,
  host_configuration_file : String,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  approval_scope : @resident.ResidentOriginalEffectApprovalScope,
  now : () -> Double,
  signer_name? : String? = None,
) -> Result[
  NativeLocalEffectReviewerBinding,
  NativeLocalEffectReviewerBindingIssue,
] {
  let installed = match
    self.install_initial_effect_reviewer(
      initial_original,
      principal,
      connection,
      host_configuration_file,
      signer_name~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.bind_selected_effect_reviewer(
    crypto,
    principal,
    connection,
    reference,
    request,
    ResidentApproval(approval_scope),
    now,
    installed,
  )
}
