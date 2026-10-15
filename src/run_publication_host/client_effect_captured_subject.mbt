///|
// A read reference within the existing captured Effect owner. It has no
// permission, Store, checkpoint-admission, cleanup or signing capability.
struct ClientCapturedEffectSubjectRead {
  preview : @strategy.CapturedEffectPreviewInputs
  invocation_cid : String
  unit_definition_cid : String
}

///|
/// Read original identities only after the caller's final current callbacks.
/// The same capture/set/pins must remain retained. This terminal fence invokes
/// no callback and does not replace availability, current RunRead/Reviewer/key
/// checks, authenticated checkpoint custody or physical resource funding.
pub fn ClientCapturedEffectSubjectRead::original_subject_after_current(
  self : ClientCapturedEffectSubjectRead,
) -> Result[(String, String), ClientEffectCheckpointBindingIssue] {
  if !@strategy.captured_effect_preview_inputs_retained(self.preview) {
    return Err(OriginalLifetime)
  }
  Ok((self.invocation_cid, self.unit_definition_cid))
}

///|
/// Project the actual captured Preview's Run Invocation and the explicit
/// Checkpoint unit from the same original compiled owner. No caller-proposed
/// Invocation/CID, source snapshot, first-unit fallback, recompile or recapture
/// is accepted. The sealed Checkpoint is nominal metadata here; its durable
/// Store/current/revision binding remains the caller's independent obligation.
/// Callers must retain this view across their own current checks and use its
/// terminal noncallback read afterwards. It cannot create an approval scope.
pub fn read_client_captured_effect_subject(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Result[ClientCapturedEffectSubjectRead, ClientEffectCheckpointBindingIssue] {
  let unit = match
    client_effect_review_checkpoint_unit_definition_cid(
      allowed, definition, checkpoint,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let owner = allowed.compilation.owner
  let checked_preview = @strategy.captured_effect_preview_owner(preview)
  let run = @checked.effect_program_run_preview_owner(checked_preview)
  if !physical_equal(
      @checked.effect_program_run_static_candidate(run),
      owner.candidate,
    ) ||
    !physical_equal(
      @checked.effect_program_run_admission(run),
      allowed.admission,
    ) ||
    @publication.publication_contract_json(
      @checked.effect_program_run_definition(run),
    ) !=
    @publication.publication_contract_json(definition) {
    return Err(ForeignSubject)
  }
  guard checkpoint.checkpoint.subject is @checkpoint.RunUnit(unit_id~, ..) else {
    return Err(ForeignSubject)
  }
  let stage = @checked.effect_program_run_preview_stage(checked_preview)
  let stages = @syntax.stages(owner.source)
  if stage < 0 || stage >= stages.length() || stages[stage].id != unit_id {
    return Err(ForeignSubject)
  }
  // Actual material availability may invoke its original owner callbacks.
  // Recheck the same retained capture afterwards, including a callback which
  // retires the input and still returns true. No availability result is cached.
  if !@strategy.captured_effect_preview_inputs_available(preview) {
    return Err(OriginalLifetime)
  }
  let read : ClientCapturedEffectSubjectRead = {
    preview,
    invocation_cid: @publication.publication_contract_identity(
      @checked.effect_program_run_preview_invocation(checked_preview),
    ),
    unit_definition_cid: unit,
  }
  read.original_subject_after_current().map(_ => read)
}
