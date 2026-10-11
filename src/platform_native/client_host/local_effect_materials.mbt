///|
/// Read original admitted materials using the currently adopted Host Account.
/// Run read does not authorize Source acquisition, Effect dispatch, approval,
/// Result delivery or a new compilation. Each journal lookup and the final
/// custody return recheck the original Host/adoption/scope and current Account.
pub fn NativeLocalHostConnection::bind_submitted_effect_original_materials(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  now : Double,
) -> Result[
  @host.ClientEffectRunMaterials,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let authority = match
    native_local_policy_authority_for(
      self,
      crypto,
      principal,
      connection,
      request,
      ReadRunMaterials,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  self.journal.bind_submitted_effect_original_materials(
    self.epoch,
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    authority.scope,
    () => authority.current_for(self.journal, request),
    now,
  )
}
