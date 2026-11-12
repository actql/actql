///|
/// Contributing Direct/Whole Source Relations for one accepted Model context.
/// This deliberately excludes the separate keyed output: a complete Artifact
/// must also retain its actual admitted lookup provenance before publication.
/// The caller backs the bounded metadata and retains the returned originals
/// before its next fallible operation, as for acquired evidence generally.
pub fn issue_single_model_client_effect_direct_source_evidence(
  compiled : ClientCompiledRun,
  scope : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
  sources : ClientInferComposedSources,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientEffectLocalInvocation, Array[ClientEffectAcquiredEvidence]),
  ClientEffectAcquiredEvidenceIssue,
] {
  // Scope admission already checked this immutable composed inventory. Keep
  // its exact original observation/Plan association; do not repeat Source
  // admission/current callbacks here. The Model original and later raw-body
  // borrow retain their own actual current boundaries.
  if !physical_equal(scope.owner, sources.occurrence.owner) ||
    !client_infer_occurrence_matches_plan(scope.plan.occurrence, scope.plan) ||
    !client_infer_composed_source_origin_matches(
      sources.occurrence,
      scope.plan.occurrence,
    ) {
    return Err(Invocation(ForeignCapturedInput))
  }
  for input in sources.inputs {
    if !scope.named_sources.any(entry => {
        entry.0 == input.name && physical_equal(entry.1, input.observation)
      }) {
      return Err(Invocation(ForeignSourceObservation))
    }
  }
  let invocation = match
    issue_single_model_client_effect_local_invocation(
      compiled, scope, model, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  build_model_effect_direct_sources(
    invocation, sources, retention, max_bytes, max_nodes, max_depth,
  ).map(entries => (invocation, entries))
}

///|
fn build_model_effect_direct_sources(
  invocation : ClientEffectLocalInvocation,
  sources : ClientInferComposedSources,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[ClientEffectAcquiredEvidence],
  ClientEffectAcquiredEvidenceIssue,
] {
  let entries = []
  for input in sources.inputs {
    let cached = sources.keyed.bind(value => {
      let lookup = value.1.lookup
      if lookup.closed || lookup.left.lookup_issue is Some(_) {
        return None
      }
      lookup.native_sources.bind(state => {
        state.sources
        .iter()
        .find_first(original => {
          physical_equal(original.identity, input.identity) &&
          physical_equal(
            original.logical,
            @publication.model_source_observation_originals(input.observation).1,
          ) &&
          physical_equal(
            original.observation,
            @publication.model_source_observation_originals(input.observation).0,
          )
        })
      })
    })
    if cached is Some(original) {
      if !@publication.result_retention_bounds_equal(
          original.retention,
          retention,
        ) {
        return Err(Relation(@publication.WrongRetention))
      }
      // Reuse the exact metadata completed before the Model Read. No second
      // Request encoding/hash, Source admission or Relation issuer is needed.
      entries.push({
        owner: invocation.owner,
        identity: input.identity,
        captured: input.source,
        purpose: ModelContribution,
        invocation,
        input: original.logical,
        observation: original.observation,
        request: original.request,
        request_cid: original.request_cid,
        retention: original.retention,
        publication_retention: retention,
        relation: original.relation,
        ordering: original.ordering,
        scope: original.scope,
      })
      continue
    }
    let material = match input.original {
      Query(requirement) => {
        let material = @planning.query_requirement_material(requirement)
        Ok(
          (
            @planning.query_material_request(material),
            @planning.query_material_cids(material).0,
          ),
        )
      }
      Whole(original) =>
        client_effect_whole_source_request_material(
          original, max_bytes, max_nodes, max_depth,
        )
    }
    let (request, request_cid) = match material {
      Ok(value) => value
      Err(issue) => return Err(Invocation(issue))
    }
    let facts = match input.original {
      Query(requirement) =>
        @planning.query_requirement_source_evidence_facts(requirement)
      Whole(original) => @planning.source_acquisition_evidence_facts(original)
    }
    guard facts is Some(facts) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    let source_retention = match
      @publication.issue_result_retention_for_data_policy(
        retention,
        facts.source_data_policy_cid,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(@publication.Contract(issue)))
    }
    let (source, logical, _, _) = @publication.model_source_observation_originals(
      input.observation,
    )
    let (relation, ordering, acquisition_scope) = match
      @publication.issue_captured_source_input_relation(
        logical,
        source,
        request_cid,
        @query.captured_source_relation_row_count(input.identity),
        source_retention,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
    entries.push({
      owner: invocation.owner,
      identity: input.identity,
      captured: input.source,
      purpose: ModelContribution,
      invocation,
      input: logical,
      observation: source,
      request,
      request_cid,
      retention: source_retention,
      publication_retention: retention,
      relation,
      ordering,
      scope: acquisition_scope,
    })
  }
  Ok(entries)
}
