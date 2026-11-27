///|
/// Prepare the final Run row from the same published result evidence and the
/// exact confirmed Applied predecessor. The caller separately commits and
/// reobserves the row under the same adopted Store and publisher.
pub fn ClientEffectSavedFilePublication::prepare_completed_state(
  self : ClientEffectSavedFilePublication,
  last : ClientEffectSavedFileTerminal,
  state_wire : String,
  at : String,
  now : Int64,
  before_encode : (Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue],
) -> Result[ClientEffectFileJournalWrite, ClientEffectResolutionOriginalIssue] {
  let application = self.completion.application
  let waiting = application.computation.preview.waiting
  let actual = saved_file_journal_successor(last.writes[0])
  let dispatch = last.response.dispatch
  let (_, rows) = application.ordered_count()
  let limits = client_checkpoint_journal_limits()
  let { checkpoint, run, policy, observation, .. } = last
  guard physical_equal(dispatch.row.application, application) &&
    dispatch.index == rows - 1 &&
    actual.revision == 5L + 3L * rows.to_int64() &&
    @publication.effect_set_apply_receipt_disposition(
      @publication.effectful_final_run_evidence_outcomes(
        self.completion.evidence,
      ),
    ) ==
    0 &&
    run.publication_binding == waiting.run.publication_binding &&
    !run.cancellation_requested() &&
    checkpoint.artifact.checkpoint_cid ==
    waiting.checkpoint.artifact.checkpoint_cid &&
    checkpoint.state.status == @publication.Resuming &&
    !checkpoint.settlement_only &&
    checkpoint.unknown_effects.is_empty() &&
    checkpoint.effect_ledger.length() == 3 * rows &&
    checkpoint.resume_intent is Some(intent) &&
    @checkpoint.decide_resume_fence(intent, application.claim.claim, now) ==
    @checkpoint.FenceCurrent &&
    @checkpoint.admit_run_state_wire(state_wire, limits) is Ok(state) &&
    state.status == @publication.Succeeded &&
    state.run_id == checkpoint.state.run_id &&
    state.wire == state_wire else {
    return Err(InvalidOriginal)
  }
  let completed = {
    ..checkpoint,
    state,
    updated_at: at,
    resume_intent: Some({ ..intent, state: @checkpoint.ResumeCompleted, }),
  }
  guard client_checkpoint_journal_row_body(completed) is Ok(wire) &&
    client_run_journal_row_body(
      { ..run, checkpoint: Some(wire), },
      local_run_policy_originals=policy,
      run_observation_originals=observation,
      measure_construction=true,
      before_construction=Some(before_encode),
    )
    is Ok(successor) else {
    return Err(Encoding)
  }
  Ok({ table: "client_runs", key: actual.key, before: Some(actual), successor, })
}

///|
/// Retain the exact already observed Index bind beside the completed Run.
/// No authoring/Preview, private continuation or new authority is copied here.
pub fn ClientEffectSavedFilePublication::prepare_completion_anchor(
  self : ClientEffectSavedFilePublication,
  identity : String,
) -> ClientEffectFileJournalWrite {
  let waiting = self.completion.application.computation.preview.waiting
  {
    table: "client_effect_publication",
    key: client_request_scope_cid(waiting.run.request),
    before: None,
    successor: client_effect_publication_anchor(
      @publication.publication_contract_identity(waiting.run.definition),
      waiting.checkpoint.artifact.checkpoint_cid,
      self.completion.final_receipt_cid(),
      identity,
    ),
  }
}
