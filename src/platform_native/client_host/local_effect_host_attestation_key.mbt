///|
// Local operational attestation only. The generic Native verifier retains its
// independently supplied installed public-authority interface. This closed
// assembly consumes the same adopted Local key original, never a caller key
// array, a copied public CID or the initialized Reviewer key as Host authority.
fn local_effect_host_attestation_authority(
  host : NativeLocalHostConnection,
  key : NativeLocalSigningKeyOriginal,
  reviewer_public_key_pem : String,
) -> Result[
  @effect_resolution.NativeEffectHostAuthority,
  NativeLocalEffectReviewerBindingIssue,
] {
  let account = key.account
  if !physical_equal(host, account.host) ||
    account.kind != @checkpoint.EffectSet ||
    account.reviewer is Some(_) {
    return Err(ReviewerUnavailable)
  }
  let (enabled, purpose, _, _, _, key_id, _, public_key_pem) = @credential_resource.native_local_signing_key_selection_projection(
    account.selection,
  )
  if !enabled || purpose != @credential.HostAttestation {
    return Err(ReviewerUnavailable)
  }
  match key.require_current_key() {
    Err(_) => return Err(ReviewerUnavailable)
    Ok(_) => ()
  }
  // Distinct roles require distinct original public bytes too. Different PEM
  // text, key labels, filenames or principals cannot make the same key another
  // attestation authority. Only the existing physical public-key decoder runs.
  let reviewer = match
    host.epoch.crypto.ed25519_public_key_raw32(reviewer_public_key_pem) {
    Err(_) => return Err(ReviewerUnavailable)
    Ok(value) => value
  }
  let original = match key.public_key.raw32() {
    Err(_) => return Err(ReviewerUnavailable)
    Ok(value) => value
  }
  if reviewer == original {
    return Err(ReviewerUnavailable)
  }
  match key.require_current_key() {
    Err(_) => return Err(ReviewerUnavailable)
    Ok(_) => ()
  }
  // No caller callback or secret read follows this actual generation fence.
  // The returned public DATA still requires exact signature verification and
  // full original Checkpoint/current admission before any resolution commit.
  guard key.projection.export_original() is Ok(actual) && actual == key.exported else {
    return Err(ReviewerUnavailable)
  }
  Ok({ key_id, public_key_pem, })
}
