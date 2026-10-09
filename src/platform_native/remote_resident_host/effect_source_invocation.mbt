///|
pub(all) enum ResidentEffectCapturedInvocationIssue {
  Unavailable
  Invocation(@publication.RunEvidenceValueIssue)
}

///|
/// Issue the Run Observation Set and Invocation from the original completed
/// Source's journal and live captured owner. The common issuer validates the
/// admitted compilation, Run and Source binding. No observation time, authority
/// or Run lifetime is renewed, and no Source acquisition is performed.
pub fn ResidentEffectProducerExecuted::invocation_for_capture(
  self : ResidentEffectProducerExecuted,
  journal : @journal.Journal,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  ResidentEffectCapturedInvocationIssue,
] {
  guard self.source_for_capture(journal) is Some(source) &&
    source.effect_source is Some(original) &&
    source.capture is Some(captured) &&
    self.materials_for_capture(journal) is Some(materials) &&
    journal.observation(self.executed.request) is Ok(saved) &&
    @journal.recovered_site_dispatch_source_observation(saved)
    is Some(observation) &&
    @remote.remote_source_observation_matches_dispatch(
      observation,
      self.executed.request,
    ) &&
    @planning.query_requirement_source_evidence_facts(original.requirement)
    is Some(facts) else {
    return Err(Unavailable)
  }
  let projection = @remote.remote_source_observation_projection(observation)
  if projection.0 != 0 {
    return Err(Unavailable)
  }
  let (source_ref, source_contract) = @planning.query_requirement_source(
    original.requirement,
  )
  let result = match
    @host.issue_client_effect_captured_invocation(
      materials.prepared,
      materials.compilation,
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      captured,
      projection.1,
      projection.2,
      source_ref,
      source_contract,
      @remote.dispatch_request_journal_key(self.executed.request)[0],
      @planning.query_source_evidence_fact_values(facts)[3],
      projection.3,
      projection.4,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  if self.source_for_capture(journal) is None {
    return Err(Unavailable)
  }
  Ok(result)
}
