///|
// Same Reviewer/Checkpoint Owner; the variants cannot exchange their distinct
// source-root configuration and authenticated initial Store originals.
priv enum NativeLocalReviewerProofKey {
  ConfiguredReviewerKey(NativeLocalSigningKeyOriginal)
  InitialReviewerKey(NativeLocalInitialReviewerSigningKey)
}

///|
priv struct NativeLocalReviewerKeyScopeFields {
  account_configuration_cid : String
  account_id : String
  authority_scope_cid : String
  host_adoption_cid : String
  key_configuration_cid : String
  key_generation_cid : String
  key_id : String
  key_public_key_cid : String
  principal : String
}

///|
/// Same initialized key generation and independently selected current Reviewer.
/// This holds projection metadata, not private key bytes, an issuer, a grant,
/// a credential use or permission to apply a Resolution.
struct NativeLocalInitialReviewerSigningKey {
  original : NativeLocalInitialSigningOriginal
  installed : NativeLocalInstalledEffectReviewer
  fields : NativeLocalReviewerKeyScopeFields
}

///|
fn NativeLocalInitialReviewerSigningKey::finish_original_projection(
  self : NativeLocalInitialReviewerSigningKey,
) -> Result[Unit, NativeLocalSigningOriginalIssue] {
  let original = self.original
  // No caller clock/current callback follows this original-generation check.
  guard self.installed.current() &&
    original.host.session.selected_configuration(self.installed.file)
    is Ok(configuration) &&
    configuration == self.installed.original_bytes &&
    original.host.database.read("client_local_installation_custody", "host")
    is Ok(row) &&
    row.revision == 0L &&
    row.body == original.control_body &&
    original.projection.export_original() is Ok(bytes) &&
    bytes == original.exported else {
    return Err(SigningOriginalUnavailable)
  }
  original.check_host_current().map_err(issue => SigningCustody(issue))
}

///|
fn NativeLocalInitialReviewerSigningKey::require_current(
  self : NativeLocalInitialReviewerSigningKey,
) -> Result[Unit, NativeLocalSigningOriginalIssue] {
  let original = self.original
  let installed = self.installed
  guard installed.initial_original is Some(retained) &&
    physical_equal(original.host, installed.host) &&
    physical_equal(retained.host, original.host) &&
    retained.control_body == original.control_body &&
    retained.exported == original.exported &&
    original.require_current() is Ok(_) &&
    installed.current() &&
    installed.reviewer.principal == self.fields.principal &&
    installed.reviewer.key_id == self.fields.key_id &&
    installed.reviewer.public_key_pem == original.public_key_pem &&
    original.authority_scope_cid(
      installed.reviewer.principal,
      installed.reviewer.connection,
    )
    is Ok(scope) &&
    scope == self.fields.authority_scope_cid &&
    original.host.session.configuration.account_id() == self.fields.account_id &&
    original.host.session.configuration.configuration_cid() ==
    self.fields.account_configuration_cid else {
    return Err(SigningOriginalUnavailable)
  }
  self.finish_original_projection()
}

///|
/// Trusted assembly selects this same initialized Store key and actual current
/// Reviewer. Configuration identity is the existing digest of the authenticated
/// initial control body, and generation identity is the existing digest of the
/// retained file projection. Neither digest manufactures adoption or authority.
/// No configured key/issuer file is synthesized and no secret is read here.
pub fn NativeLocalHostConnection::acquire_initial_reviewer_signing_key(
  self : NativeLocalHostConnection,
  original : NativeLocalInitialSigningOriginal,
  installed : NativeLocalInstalledEffectReviewer,
) -> Result[
  NativeLocalInitialReviewerSigningKey,
  NativeLocalSigningOriginalIssue,
] {
  guard physical_equal(self, original.host) &&
    physical_equal(self, installed.host) &&
    installed.initial_original is Some(retained) &&
    retained.control_body == original.control_body &&
    retained.exported == original.exported &&
    installed.current() &&
    original.require_current() is Ok(_) else {
    return Err(SigningOriginalUnavailable)
  }
  let configuration_cid = match
    local_adoption_digest(self.epoch.crypto, original.control_body) {
    Ok(value) => value
    Err(issue) => return Err(SigningCustody(issue))
  }
  let generation_cid = match
    local_adoption_digest(self.epoch.crypto, original.exported) {
    Ok(value) => value
    Err(issue) => return Err(SigningCustody(issue))
  }
  let scope = match
    original.authority_scope_cid(
      installed.reviewer.principal,
      installed.reviewer.connection,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SigningCustody(issue))
  }
  let key : NativeLocalInitialReviewerSigningKey = {
    original,
    installed,
    fields: {
      account_configuration_cid: self.session.configuration.configuration_cid(),
      account_id: self.session.configuration.account_id(),
      authority_scope_cid: scope,
      host_adoption_cid: self.adoption_cid,
      key_configuration_cid: configuration_cid,
      key_generation_cid: generation_cid,
      key_id: original.public_key.cid(),
      key_public_key_cid: original.public_key.cid(),
      principal: installed.reviewer.principal,
    },
  }
  key.require_current().map(_ => key)
}

///|
fn NativeLocalInitialReviewerSigningKey::read_current_reviewer(
  self : NativeLocalInitialReviewerSigningKey,
  binding : NativeLocalEffectReviewerBinding,
) -> Result[
  @effect_resolution.NativeEffectReviewerRegistration,
  NativeLocalSigningOriginalIssue,
] {
  let installed = self.installed
  guard physical_equal(binding.host, self.original.host) &&
    binding.installed.initial_original is Some(_) &&
    binding.installed.file == installed.file &&
    binding.installed.original_bytes == installed.original_bytes &&
    binding.installed.reviewer == installed.reviewer else {
    return Err(SigningOriginalUnavailable)
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let selected = binding.selected()
  guard binding.read_current(selected, self.fields.key_id) is Some(registration) &&
    registration.selection == selected &&
    registration.reviewer_id == installed.reviewer.reviewer_id &&
    registration.key_id == self.fields.key_id &&
    registration.public_key_pem == self.original.public_key_pem &&
    registration.authority_context_cid == self.fields.authority_scope_cid &&
    registration.policy_cid == self.fields.account_configuration_cid else {
    return Err(SigningOriginalUnavailable)
  }
  // read_current already checks the original Client before/after its clock
  // and paired-subject callbacks, then the selected Reviewer/Host. Re-entering
  // it would run those same callbacks again. Finish the SAME key/registration
  // projection after the last callback; equal bytes cannot replace its file
  // generation and this does not grant a signature or a credential use.
  self.finish_original_projection().map(_ => registration)
}

///|
/// The same Checkpoint snapshot, unsigned proof, original Submission and paired
/// subject readers are shared with configured keys. This never recreates their
/// originals or supplies missing physical issuer/use/signature custody.
pub fn NativeLocalInitialReviewerSigningKey::prepare_reviewer_proof_materials(
  self : NativeLocalInitialReviewerSigningKey,
  reviewer : NativeLocalEffectReviewerBinding,
  unsigned_wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[
  NativeLocalReviewerProofMaterials,
  NativeLocalReviewerProofMaterialsIssue,
] {
  prepare_local_reviewer_proof_materials(
    InitialReviewerKey(self),
    reviewer,
    unsigned_wire,
    limits,
  )
}

///|
fn NativeLocalReviewerProofKey::read_current_reviewer(
  self : NativeLocalReviewerProofKey,
  binding : NativeLocalEffectReviewerBinding,
) -> Result[
  @effect_resolution.NativeEffectReviewerRegistration,
  NativeLocalSigningOriginalIssue,
] {
  match self {
    ConfiguredReviewerKey(key) => key.read_current_reviewer(binding)
    InitialReviewerKey(key) => key.read_current_reviewer(binding)
  }
}

///|
fn NativeLocalReviewerProofKey::scope_fields(
  self : NativeLocalReviewerProofKey,
) -> NativeLocalReviewerKeyScopeFields {
  match self {
    InitialReviewerKey(key) => key.fields
    ConfiguredReviewerKey(key) => {
      let account = key.account
      let (_, _, principal, _, _, key_id, _, _) = @credential_resource.native_local_signing_key_selection_projection(
        account.selection,
      )
      {
        account_configuration_cid: account.account_configuration_cid,
        account_id: account.account_id,
        authority_scope_cid: account.scope,
        host_adoption_cid: account.host.adoption_cid,
        key_configuration_cid: account.file.content_cid,
        key_generation_cid: key.generation_cid,
        key_id,
        key_public_key_cid: key.public_key.cid(),
        principal,
      }
    }
  }
}

///|
fn NativeLocalReviewerProofKey::finish_original_projection(
  self : NativeLocalReviewerProofKey,
) -> Result[Unit, NativeLocalReviewerProofMaterialsIssue] {
  match self {
    InitialReviewerKey(key) =>
      key.finish_original_projection().map_err(issue => ProofKey(issue))
    ConfiguredReviewerKey(key) => {
      // The shared proof's final clock callback may also replace the original
      // configured selection or retire its Account/Reviewer authority.
      match key.require_current_key() {
        Err(issue) => return Err(ProofKey(issue))
        Ok(_) => ()
      }
      match key.projection.export_original() {
        Ok(bytes) if bytes == key.exported => Ok(())
        _ => Err(ProofKey(SigningOriginalUnavailable))
      }
    }
  }
}

///|
fn NativeLocalReviewerProofKey::require_signing_key_scope(
  self : NativeLocalReviewerProofKey,
  scope : @credential.LocalSigningCredentialScope,
) -> Result[Unit, NativeLocalReviewerProofMaterialsIssue] {
  match self {
    ConfiguredReviewerKey(key) => key.require_reviewer_signing_key_scope(scope)
    InitialReviewerKey(key) => {
      match key.require_current() {
        Err(issue) => return Err(ProofKey(issue))
        Ok(_) => ()
      }
      let facts = key.fields
      if scope.purpose != @credential.ReviewerProof ||
        scope.checkpoint_kind != @checkpoint.EffectSet ||
        scope.account_configuration_cid != facts.account_configuration_cid ||
        scope.account_id != facts.account_id ||
        scope.authority_scope_cid != facts.authority_scope_cid ||
        scope.host_adoption_cid != facts.host_adoption_cid ||
        scope.key_configuration_cid != facts.key_configuration_cid ||
        scope.key_generation_cid != facts.key_generation_cid ||
        scope.key_id != facts.key_id ||
        scope.key_public_key_cid != facts.key_public_key_cid ||
        scope.principal != facts.principal {
        return Err(ProofUnavailable)
      }
      key.finish_original_projection().map_err(issue => ProofKey(issue))
    }
  }
}
