///|
/// Host signing keys are independently installed. Submitted keys, Source
/// grants and Workspace membership cannot replace reviewer authorization.
pub(all) struct NativeEffectHostAuthority {
  key_id : String
  public_key_pem : String
}

///|
pub(all) enum NativeResidentEffectResolutionIssue {
  Unavailable
  AuthorityDenied
  AttestationRejected
  Signature(@signature.NativeSignatureIssue)
  Resolution(@checkpoint.ResolutionIssue)
  Retention(@resident.ResidentEffectReviewRetentionIssue)
}

///|
/// Admit the exact common Resolution against this live holder's confirmed
/// original Checkpoint. Current authority is independently supplied by the
/// existing Host authorization Owner; historical signed facts grant no role.
/// This returns no claim, Provider-send permit, terminality or cleanup proof.
pub fn NativeResidentEffectReview::admit_resolution(
  self : NativeResidentEffectReview,
  verified_wire : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  host_authorities : Array[NativeEffectHostAuthority],
  current : () -> Bool,
  now : () -> String,
) -> Result[@checkpoint.VerifiedResolution, NativeResidentEffectResolutionIssue] {
  guard current() &&
    self.current() &&
    self.retention is Some(retention) &&
    self.retention_configuration is Some((crypto, _, _, _, _, limits)) else {
    return Err(Unavailable)
  }
  let report = match retention.report() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
  let admitted = match
    admit_native_effect_resolution(
      crypto, checkpoint, verified_wire, authentication, reviewers, host_authorities,
      current, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Reentrant authorization and physical verification cannot retire or
  // replace this holder's original retained input behind the admission.
  let current_time = now()
  let current_authority = current()
  if !current_authority ||
    !self.current() ||
    !@host.client_effect_run_start_current(
      self.materials.allowed,
      self.materials.run_definition,
      current_time,
    ) {
    return Err(AuthorityDenied)
  }
  let confirmed = match retention.report() {
    Ok(value) => value
    Err(issue) => return Err(Retention(issue))
  }
  if @remote.remote_effect_checkpoint_report_identity(confirmed) !=
    @remote.remote_effect_checkpoint_report_identity(report) {
    return Err(Unavailable)
  }
  Ok(admitted)
}

///|
/// Verify existing common admission with current independent authorization
/// and installed Host keys. This grants no claim or physical execution permit.
pub fn admit_native_effect_resolution(
  crypto : @signature.Library,
  checkpoint : @checkpoint.SealedCheckpoint,
  verified_wire : String,
  authentication : @checkpoint.HostAuthentication,
  reviewers : Array[@checkpoint.ReviewerAuthority],
  host_authorities : Array[NativeEffectHostAuthority],
  current : () -> Bool,
  limits : @checkpoint.WireLimits,
) -> Result[@checkpoint.VerifiedResolution, NativeResidentEffectResolutionIssue] {
  if !current() {
    return Err(AuthorityDenied)
  }
  let admitted = match
    @checkpoint.admit_attested_effect_resolution(
      checkpoint, verified_wire, authentication, reviewers, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resolution(issue))
  }
  let selected = host_authorities.filter(authority => {
    authority.key_id == admitted.host_key_id
  })
  if selected.length() != 1 || selected[0].public_key_pem.is_empty() {
    return Err(AttestationRejected)
  }
  // Checkpoint wire uses canonical padded Base64. The existing Native
  // signature API consumes unpadded Base64url; change only that transport
  // encoding, never the signed preimage or stored wire.
  let signature_bytes = @base64.decode(admitted.signature[:]) catch {
    _ => return Err(AttestationRejected)
  }
  if signature_bytes.length() != 64 ||
    @base64.encode(signature_bytes) != admitted.signature {
    return Err(AttestationRejected)
  }
  let signature_url = @base64.encode(signature_bytes, padding=false)
    .replace_all(old="+", new="-")
    .replace_all(old="/", new="_")
  match
    crypto.verify_ed25519(
      selected[0].public_key_pem,
      @utf8.encode(admitted.attestation_preimage),
      signature_url,
    ) {
    Ok(true) => ()
    Ok(false) => return Err(AttestationRejected)
    Err(issue) => return Err(Signature(issue))
  }
  if !current() {
    return Err(AuthorityDenied)
  }
  Ok(admitted.resolution)
}
