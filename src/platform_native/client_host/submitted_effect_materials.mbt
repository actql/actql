///|
pub(all) enum NativeClientSubmittedEffectMaterialsIssue {
  Journal(NativeClientRunJournalIssue)
  MissingRunAdmission
  UnresolvedHistory
  ForeignPreparation
  ChangedIntent
  ForeignRun
  Materials(@host.ClientEffectRunMaterialsIssue)
}

///|
/// Join the original durable Submission admission to live original materials.
/// This is not acceptance, restoration from candidate wire, a work claim or
/// Provider permission. The Host supplies current Run authority at each lookup.
/// Already-started or cancelled work remains owned by its original Run.
pub fn NativeClientRunJournal::bind_submitted_effect_original_materials(
  self : NativeClientRunJournal,
  authority : NativeClientEpochAuthority,
  reference : NativeClientSubmissionReference,
  preparation : NativeClientSubmittedPreparation,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : @host.ClientEffectIssuedNormalizationMaterials,
  authority_scope_cid : String,
  current_authorization : () -> Bool,
  now : Double,
) -> Result[
  @host.ClientEffectRunMaterials,
  NativeClientSubmittedEffectMaterialsIssue,
] {
  let original = match
    self.lookup_submitted_intent(
      authority,
      reference,
      authority_scope_cid,
      current_authorization(),
      now,
    ) {
    Ok(Submitted(value)) => value
    Ok(UnresolvedSubmissionHistory) => return Err(UnresolvedHistory)
    Err(issue) => return Err(Journal(issue))
  }
  if @host.client_submitted_intent_cid(original.intent) !=
    preparation.intent_cid {
    return Err(ChangedIntent)
  }
  guard original.run_admission is Some(admission) else {
    return Err(MissingRunAdmission)
  }
  if @host.client_request_identity_relation(admission.request, request) !=
    @host.SameRequest {
    return Err(ChangedIntent)
  }
  let run_cid = @publication.publication_contract_identity(definition)
  if admission.run_definition_cid != run_cid {
    return Err(ForeignRun)
  }
  guard preparation.preparation is EffectComputation(prepared) else {
    return Err(ForeignPreparation)
  }
  if !physical_equal(
      prepared,
      @host.client_effect_compilation_owner(allowed.compilation),
    ) {
    return Err(ForeignPreparation)
  }
  match self.lookup(request, current_authorization()) {
    Ok(Retained(record)) =>
      if @publication.publication_contract_identity(record.definition) !=
        run_cid {
        return Err(ForeignRun)
      }
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  // Lookup is a read of each existing Owner, not an atomic control snapshot.
  // Recheck current authority immediately before exposing live material custody.
  // Do not clear cancellation, claim work or save a new journal revision here.
  if !current_authorization() {
    return Err(Journal(AuthorizationDenied))
  }
  @host.bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).map_err(issue => Materials(issue))
}
