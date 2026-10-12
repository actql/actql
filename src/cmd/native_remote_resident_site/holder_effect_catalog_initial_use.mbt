///|
/// A private caller seam for the existing consumer/Journal/Resource Owners.
/// The claim stays task-owned through failed selection or retention. These
/// fields issue no new custody, permission, reservation or send evidence.
priv struct HolderEffectCatalogInitialUse {
  original : HolderEffectOriginalPolicyContext
  grant : @effect_credential.RemoteCredentialGrant
  scope : @effect_resource.NativeCredentialScope
  use_id : String
  mut attempted : Bool
  mut claim : @journal.NativeInitialCatalogUseClaim?
  mut issue : @journal.NativeRemoteJournalIssue?
}

///|
fn holder_catalog_initial_scope_matches(
  expected : @effect_resource.NativeCredentialScope,
  proposed : @effect_resource.NativeCredentialScope,
) -> Bool {
  expected.principal == proposed.principal &&
  expected.namespace_id == proposed.namespace_id &&
  expected.environment == proposed.environment &&
  expected.site_key == proposed.site_key &&
  expected.site_generation == proposed.site_generation &&
  expected.runtime_bundle_cid == proposed.runtime_bundle_cid &&
  expected.connector_registration == proposed.connector_registration &&
  expected.connector_revision == proposed.connector_revision &&
  expected.resource_origin == proposed.resource_origin &&
  expected.operation == proposed.operation &&
  expected.run_invocation_cid == proposed.run_invocation_cid &&
  expected.task_attempt == proposed.task_attempt &&
  expected.dispatch_request_cid == proposed.dispatch_request_cid
}

///|
fn HolderEffectCatalogInitialUse::ready(
  self : HolderEffectCatalogInitialUse,
) -> Result[Unit, @journal.NativeRemoteJournalIssue] {
  if self.attempted {
    return Err(@journal.StateCollision)
  }
  if !self.original.current() {
    return Err(@journal.StaleSiteBinding)
  }
  let observed = self.original.consumer.read_initial_catalog_use(
    self.original.journal,
    self.original.producer,
  )
  if !self.original.current() {
    return Err(@journal.StaleSiteBinding)
  }
  observed
}

///|
fn HolderEffectCatalogInitialUse::claim_use(
  self : HolderEffectCatalogInitialUse,
  grant : @effect_credential.RemoteCredentialGrant,
  use_id : String,
  scope : @effect_resource.NativeCredentialScope,
) -> Result[Unit, @effect_resource.NativeCredentialResourceIssue] {
  if self.attempted ||
    !self.original.current() ||
    @effect_credential.credential_grant_cid(grant) !=
    @effect_credential.credential_grant_cid(self.grant) ||
    use_id != self.use_id ||
    !holder_catalog_initial_scope_matches(self.scope, scope) {
    return Err(@effect_resource.AccessDenied)
  }
  // Before the irreversible transaction: an error can be an unknown commit,
  // never permission to claim another initial responsibility on the next call.
  self.attempted = true
  match
    self.original.consumer.claim_initial_catalog_use(
      self.original.journal,
      self.original.producer,
    ) {
    Ok(claim) => self.claim = Some(claim)
    Err(issue) => {
      self.issue = Some(issue)
      return Err(@effect_resource.AccessDenied)
    }
  }
  if !self.original.current() {
    self.issue = Some(@journal.StaleSiteBinding)
    return Err(@effect_resource.AccessDenied)
  }
  Ok(())
}

///|
fn HolderEffectCatalogInitialUse::retain_use(
  self : HolderEffectCatalogInitialUse,
  credential_use : @effect_credential.RemoteCredentialUse,
) -> Result[Unit, @effect_resource.NativeCredentialResourceIssue] {
  guard self.claim is Some(claim) &&
    @effect_credential.credential_use_projection(credential_use)[2] ==
    self.use_id else {
    return Err(@effect_resource.AccessDenied)
  }
  // Save the original Resource-selected fact even if its caller subsequently
  // loses disclosure permission. Journal and Resource final fences decide
  // whether a send remains valid; saving the fact is not permission to send.
  match
    self.original.journal.retain_initial_catalog_use(
      claim,
      self.grant,
      credential_use,
    ) {
    Ok(_) => Ok(())
    Err(issue) => {
      if self.issue is None {
        self.issue = Some(issue)
      }
      Err(@effect_resource.AccessDenied)
    }
  }
}

///|
/// This restoration error alone is never unsent evidence. Only a successful
/// read of the original funded eligibility can select the separate first-use
/// path; the actual Resource hook must still claim it transactionally.
fn holder_catalog_initial_read_ready(
  issue : HolderCatalogUseObservationIssue,
  read_ready : () -> Result[Unit, @journal.NativeRemoteJournalIssue],
) -> Bool {
  match issue {
    Original(@journal.Physical(@sqlite.NotFound)) => read_ready() is Ok(_)
    _ => false
  }
}
