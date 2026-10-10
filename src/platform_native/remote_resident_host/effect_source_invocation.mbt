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

///|
pub(all) enum ResidentEffectSourceInvocationIssue {
  Unavailable
  ForeignRun
  Observation(ResidentSourcePublicationObservationIssue)
  Invocation(@publication.RunEvidenceValueIssue)
}

///|
/// Bind the original acquired Source to its checked Effect invocation without
/// inventing a Remote dispatch or an imported receiver. The caller supplies
/// its retained acquisition interval and current read authority. The checked
/// requirement supplies Source identity and Policy; equal bytes or a current
/// replacement configuration cannot replace the physical acquisition Owner.
pub fn ResidentSourceCompute::effect_source_publication_invocation(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  request : @host.ClientRequestIdentity,
  capture_started_at : String,
  capture_completed_at : String,
  limits : @host.PublicationOutputExportLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    ResidentSourcePublicationObservation,
    @publication.RunEvidenceValue,
    @publication.PublicationContract,
  ),
  ResidentEffectSourceInvocationIssue,
] {
  guard !self.stopping &&
    !self.source_closed.val &&
    self.effect_source is Some(original) &&
    self.capture is Some(captured) &&
    self.effect_run is Some(run) else {
    return Err(Unavailable)
  }
  match
    @host.bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(_) => ()
    Err(_) => return Err(ForeignRun)
  }
  if materials.request != Some(request) ||
    !physical_equal(materials.prepared, original.owner) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !@strategy.captured_effect_run_matches_checked(
      run,
      @host.prepared_client_effect_run_graph(original.bound),
    ) ||
    @publication.publication_contract_identity(materials.run_definition) !=
    @publication.publication_contract_identity(
      @checked.effect_program_run_definition(
        @strategy.checked_effect_run_owner(
          @host.prepared_client_effect_run_graph(original.bound),
        ),
      ),
    ) ||
    @host.prepared_client_effect_request_scope(materials.prepared, request)
    is Err(_) {
    return Err(ForeignRun)
  }
  let source = match
    self.source_publication_observation(
      @host.client_request_authority_scope_cid(request),
      capture_completed_at,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let (evidence, logical, source_ref, contract, policy) = resident_source_publication_observation_values(
    source,
  )
  let (observation, invocation) = match
    @host.issue_client_effect_captured_invocation(
      materials.prepared,
      materials.compilation,
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      captured,
      @publication.run_evidence_value_json(evidence),
      @publication.run_evidence_value_json(logical),
      source_ref,
      contract,
      @host.client_request_authority_scope_cid(request),
      policy,
      capture_started_at,
      capture_completed_at,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  if self.stopping || self.source_closed.val {
    return Err(Unavailable)
  }
  Ok((source, observation, invocation))
}
