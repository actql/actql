///|
/// Read the UnitDefinition from the original checked owner selected by this
/// nominal Checkpoint's explicit RunUnit coordinate. This pure projection
/// performs no prepare, compile, capture, permission or signing operation.
pub fn client_effect_review_checkpoint_unit_definition_cid(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  artifact : @checkpoint.SealedCheckpoint,
) -> Result[String, ClientEffectCheckpointBindingIssue] {
  let prepared = allowed.compilation.owner
  match bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  match validate_client_effect_review_checkpoint_subject(allowed, definition, artifact) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard artifact.checkpoint.subject is @checkpoint.RunUnit(unit_id~, ..) else {
    return Err(ForeignSubject)
  }
  let stages = @syntax.stages(prepared.source)
  let program = @checked.effect_program_static_checked_computation(prepared.candidate)
  if @checked.unit_count(program) != stages.length() {
    return Err(UnsupportedReview)
  }
  let mut selected : Int? = None
  for index in 0..<stages.length() {
    if stages[index].id == unit_id {
      if selected is Some(_) {
        return Err(UnsupportedReview)
      }
      selected = Some(index)
    }
  }
  guard selected is Some(index) &&
    @checked.unit_definition_cid(program, index) is Some(cid) else {
    return Err(ForeignSubject)
  }
  Ok(cid)
}
