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

///|
pub(all) enum ClientWaitingCheckpointRecordIssue {
  Expired
  State(@checkpoint.RunStateWireIssue)
  InvalidMaterial
}

///|
/// Construct and read-admit the existing waiting row for the confirmed
/// Checkpoint. The caller still owns the physical Run, current authority and
/// atomic Journal transaction.
pub fn prepare_client_waiting_checkpoint_record(
  definition : @publication.PublicationContract,
  persisted : @checkpoint.PersistedCheckpoint,
  declared_results : Array[String],
  unknown_effects : Array[String],
  binding : @checkpoint.ResumeBinding,
  updated_at : String,
  ledger_limits : @checkpoint.WireLimits,
) -> Result[(ClientCheckpointJournalRecord, String), ClientWaitingCheckpointRecordIssue] {
  let artifact = persisted.artifact
  if updated_at < artifact.checkpoint.created_at ||
    @checkpoint.checkpoint_expired_at(artifact, updated_at) != Ok(false) {
    return Err(Expired)
  }
  let limits = client_checkpoint_journal_limits()
  let wire = match
    @checkpoint.issue_waiting_run_state(
      persisted, updated_at, declared_results, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(State(issue))
  }
  guard @checkpoint.admit_run_state_wire(wire, limits) is Ok(state) else {
    return Err(InvalidMaterial)
  }
  let record : ClientCheckpointJournalRecord = {
    artifact,
    declared_results,
    unknown_effects: unknown_effects.copy(),
    updated_at,
    state,
    binding,
    resolution_cid: None,
    verified_wire: None,
    resume_intent_id: None,
    resume_intent: None,
    settlement_only: false,
    effect_ledger: [],
  }
  guard client_checkpoint_journal_row_body(record) is Ok(body) &&
    decode_client_checkpoint_journal_row(
      body, definition, ledger_limits,
    ) is Ok(_) else {
    return Err(InvalidMaterial)
  }
  Ok((record, body))
}
