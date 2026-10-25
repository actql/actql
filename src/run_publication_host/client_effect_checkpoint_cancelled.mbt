///|
pub(all) enum ClientEffectCheckpointCancelledIssue {
  Binding(ClientEffectCheckpointBindingIssue)
  Checkpoint(@checkpoint.CheckpointIssue)
  RunState(@publication.RunStateIssue)
}

///|
/// Encode confirmed whole-Run cancellation DATA for the same stored review.
/// The original Host must independently establish no grant, dispatch, unknown
/// outcome or publication and actual stopping/current/CAS. No Bool or task
/// cleanup observation is upgraded to those facts by this pure projection.
pub fn client_effect_review_checkpoint_cancelled_state(
  original : @checkpoint.SealedCheckpoint,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  stored_wire : String,
  updated_at : String,
  declared_results : Array[String],
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientEffectCheckpointCancelledIssue] {
  match @checkpoint.confirm_checkpoint_persisted(original, stored_wire) {
    Ok(_) => ()
    Err(issue) => return Err(Checkpoint(issue))
  }
  match
    validate_client_effect_review_checkpoint_subject(
      allowed, definition, original,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  match
    bind_client_effect_compiled_run(
      allowed.compilation.owner,
      allowed,
      definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(Run(issue)))
  }
  let run_id = match @publication.run_definition_run_id(definition) {
    Ok(value) => value
    Err(_) => return Err(Binding(ForeignSubject))
  }
  @publication.issue_confirmed_cancelled_unpublished_run_state_wire(
    run_id,
    updated_at,
    declared_results,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ).map_err(issue => RunState(issue))
}
