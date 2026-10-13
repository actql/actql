///|
// Pure correspondence only. Neither this comparison nor a copied registration
// supplies authorization, original key custody, a grant or a signing claim.
fn local_reviewer_signing_registration_matches(
  selection : @credential_resource.NativeLocalSigningKeySelection,
  scope : String,
  policy : String,
  selected : @effect_resolution.NativeEffectReviewerSelection,
  installed : NativeLocalEffectReviewerSelection,
  registration : @effect_resolution.NativeEffectReviewerRegistration,
) -> Bool {
  let (enabled, purpose, principal, connection, _, key_id, _, public_key) = @credential_resource.native_local_signing_key_selection_projection(
    selection,
  )
  enabled &&
  purpose == @credential.ReviewerProof &&
  @credential_resource.native_local_signing_key_selection_allows_kind(
    selection,
    @checkpoint.EffectSet,
  ) &&
  installed.enabled &&
  principal == installed.principal &&
  connection == installed.connection &&
  key_id == installed.key_id &&
  public_key == installed.public_key_pem &&
  selected.principal_id == installed.principal &&
  registration.selection == selected &&
  registration.key_id == installed.key_id &&
  registration.reviewer_id == installed.reviewer_id &&
  registration.public_key_pem == installed.public_key_pem &&
  registration.authority_context_cid == scope &&
  registration.policy_cid == policy
}

///|
/// Read the existing independent Reviewer registration while revalidating this
/// authenticated original key. The original Client's read/Approval scope is
/// still checked by the existing Reviewer binding; it is not the signer's
/// authority context. This returns metadata, never an approval, key body,
/// signing grant, use claim or signature. Exact Checkpoint-owned preimage and
/// issuer-selected original grant bindings remain separate prerequisites.
pub fn NativeLocalSigningKeyOriginal::read_current_reviewer(
  self : NativeLocalSigningKeyOriginal,
  binding : NativeLocalEffectReviewerBinding,
) -> Result[
  @effect_resolution.NativeEffectReviewerRegistration,
  NativeLocalSigningOriginalIssue,
] {
  let account = self.account
  guard physical_equal(account.host, binding.host) &&
    account.kind == @checkpoint.EffectSet &&
    account.reviewer is Some(installed) &&
    physical_equal(installed.host, binding.host) &&
    installed.file == binding.installed.file &&
    installed.original_bytes == binding.installed.original_bytes &&
    installed.reviewer == binding.installed.reviewer else {
    return Err(SigningOriginalUnavailable)
  }
  match self.require_current_key() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let selected = binding.selected()
  let registration = match
    binding.read_current(selected, installed.reviewer.key_id) {
    Some(value) => value
    None => return Err(SigningOriginalUnavailable)
  }
  if !local_reviewer_signing_registration_matches(
      account.selection,
      account.scope,
      account.account_configuration_cid,
      selected,
      installed.reviewer,
      registration,
    ) {
    return Err(SigningOriginalUnavailable)
  }
  // The original Root/file generation, Account and Checkpoint are all read
  // again. No Allow is cached, no installation is captured on restore, and
  // this read never acquires or renews a credential use ordinal.
  match self.require_current_key() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if binding.read_current(selected, registration.key_id) != Some(registration) {
    return Err(SigningOriginalUnavailable)
  }
  match self.require_current_key() {
    Ok(_) => Ok(registration)
    Err(issue) => Err(issue)
  }
}
