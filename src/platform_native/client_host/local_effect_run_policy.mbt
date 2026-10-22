///|
/// Accept an original source-free Effect Values Run with its regular finite
/// Retention and DataPolicy in the same existing journal transaction. The
/// trusted caller passes the initial observation used for the Run definition;
/// an accepted request always selects its saved original before considering it.
/// This neither dispatches Compute nor issues a read/Effect/signing grant.
pub fn NativeLocalRunPolicyBinding::accept_submitted_effect_values_run_policy(
  self : NativeLocalRunPolicyBinding,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  observed_at : String,
  now : Double,
) -> Result[
  NativeClientSubmittedIntentRecord,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let original = match
    self.prepare_submission_policy(
      reference, preparation, request, observed_at, now,
    ) {
    Ok(Accepted(saved)) => saved
    Ok(Pending(retention, issued_at)) => {
      let ref_record = reference.original
      match
        @host.bind_client_local_run_policy_original(
          self.profile,
          ref_record,
          request,
          definition,
          retention,
          issued_at,
          self.host.adoption_cid(),
          self.read_selection_cid,
        ) {
        Ok(value) => value
        Err(_) => return Err(Journal(CustodyLost))
      }
    }
    Err(issue) => return Err(Journal(issue))
  }
  self.host.accept_submitted_effect_material_with_policy(
    self.crypto,
    self.principal,
    self.connection,
    reference,
    preparation,
    request,
    allowed,
    definition,
    issued,
    now,
    Some(self.run_file.name),
    Some((self, original)),
  )
}
