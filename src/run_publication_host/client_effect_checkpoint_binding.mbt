///|
pub(all) enum ClientEffectCheckpointBindingIssue {
  Run(ClientEffectCompiledRunIssue)
  Checkpoint(@checkpoint.CheckpointIssue)
  ForeignSubject
  UnsupportedReview
  OriginalLifetime
}

///|
/// Bind already-sealed metadata to the original checked Effect Run and unit.
/// This proves no Provider work, private evidence persistence, current Site
/// authority, Run waiting commit, approval or permission to execute an Effect.
/// Authenticated Native custody and the Run revision remain separate obligations.
pub fn admit_client_effect_review_checkpoint_binding(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  wire : String,
  limits : @checkpoint.WireLimits,
) -> Result[@checkpoint.SealedCheckpoint, ClientEffectCheckpointBindingIssue] {
  match
    bind_client_effect_compiled_run(
      allowed.compilation.owner,
      allowed,
      definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  let artifact = match @checkpoint.admit_checkpoint_wire(wire, limits) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(issue))
  }
  validate_client_effect_review_checkpoint_subject(
    allowed, definition, artifact,
  ).map(_ => artifact)
}

///|
/// Read the immutable metadata of the already admitted original. This does
/// not re-admit its wire or confirm persistence, current authority or approval.
pub fn client_effect_review_checkpoint_binding_fields(
  artifact : @checkpoint.SealedCheckpoint,
) -> Result[Array[String], ClientEffectCheckpointBindingIssue] {
  let fields = [artifact.checkpoint_cid, artifact.wire]
  match artifact.checkpoint.subject {
    @checkpoint.RunUnit(run_id~, unit_id~, run_definition_cid~) => {
      fields.push(run_id)
      fields.push(unit_id)
      fields.push(run_definition_cid)
    }
    _ => return Err(ForeignSubject)
  }
  fields.push(artifact.checkpoint.required_artifact_cid)
  fields.push(artifact.checkpoint.review_projection_cid)
  fields.push(artifact.checkpoint.continuation_state_cid)
  Ok(fields)
}

///|
// Shared pure nominal-subject validation after the original compiled Run bind.
// The wire reader keeps its original bind -> decode -> validation order.
fn validate_client_effect_review_checkpoint_subject(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  artifact : @checkpoint.SealedCheckpoint,
) -> Result[Unit, ClientEffectCheckpointBindingIssue] {
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return Err(ForeignSubject)
  }
  let expected = @checkpoint.RunUnit(
    run_id~,
    unit_id=client_effect_compilation_unit_id(allowed.compilation),
    run_definition_cid=@publication.publication_contract_identity(definition),
  )
  if artifact.checkpoint.subject != expected {
    return Err(ForeignSubject)
  }
  if artifact.checkpoint.phase != @checkpoint.Commit ||
    artifact.checkpoint.kind != @checkpoint.EffectSet ||
    artifact.checkpoint.requirements != [@checkpoint.EffectScopeApproved] {
    return Err(UnsupportedReview)
  }
  // Inspection remains possible after expiry. These checks prohibit extending
  // the ORIGINAL evidence window; a current start/approval check is separate.
  guard @publication.run_definition_lifetime(definition) is Some((_, until)) else {
    return Err(OriginalLifetime)
  }
  // Both lifetimes have an exclusive end. The Checkpoint may end exactly at
  // the Run deadline; this is interval containment, not a start at that time.
  // Checking its creation with the original admission also preserves the
  // Run/admission deadline and immutable compilation/context correspondence.
  if !client_effect_run_start_current(
      allowed,
      definition,
      artifact.checkpoint.created_at,
    ) ||
    artifact.checkpoint.expires_at > until {
    return Err(OriginalLifetime)
  }
  Ok(())
}
