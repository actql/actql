///|
pub(all) enum ClientEffectCheckpointWaitingIssue {
  Checkpoint(@checkpoint.CheckpointIssue)
  RunState(@checkpoint.RunStateWireIssue)
}

///|
/// Project the original admitted Checkpoint after its caller supplies the
/// actual stored wire. Physical custody/revision and current authority remain
/// with that operation; this function issues neither a Store ACK nor permission.
pub fn client_effect_review_checkpoint_waiting_state(
  original : @checkpoint.SealedCheckpoint,
  stored_wire : String,
  updated_at : String,
  declared_results : Array[String],
  limits : @checkpoint.WireLimits,
) -> Result[String, ClientEffectCheckpointWaitingIssue] {
  let persisted = match
    @checkpoint.confirm_checkpoint_persisted(original, stored_wire) {
    Ok(value) => value
    Err(issue) => return Err(Checkpoint(issue))
  }
  @checkpoint.issue_waiting_run_state(
    persisted, updated_at, declared_results, limits,
  ).map_err(issue => RunState(issue))
}
