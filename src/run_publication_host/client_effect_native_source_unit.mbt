///|
/// Local Unit provenance from the original Native whole-Source metadata. This
/// is a separate checked producer entrance, never a ModelContribution upgrade.
/// No Source is read, admitted or encoded again; the live lookup retains the
/// actual capture, immutable request and complete Source protocol originals.
pub fn issue_client_keyed_native_effect_source_unit(
  owner : PreparedClientEffectComputation,
  lookup : ClientKeyedLookupInput,
  index : Int,
  publication_retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectAcquiredEvidence, ClientEffectAcquiredEvidenceIssue] {
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.left.composed is Some(composed) &&
    composed.keyed.program is KeyedEffect(original) &&
    physical_equal(original, owner) &&
    lookup.native_sources is Some(state) &&
    state.sources.get(index) is Some(evidence) &&
    composed.sources.get(index) is Some(captured) &&
    @query.captured_source_relation_identity_matches_source(
      evidence.identity,
      captured,
    ) &&
    select_client_direct_acquisition_occurrences(composed.plan.owner, 1000000)
    is Ok(direct) &&
    client_direct_acquisition_occurrence_at(direct, index)
    is Some((unit, _, task)) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard task == unit &&
    // Only a distinct completed producer Unit can supply this entrance.
    // An inline Source/Model Unit needs its Model observation as well.
    unit < composed.plan.occurrence.stage &&
    unit < @strategy.graph_captured_prefix(graph) &&
    @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) else {
    return Err(Invocation(MissingUnit))
  }
  if !@publication.result_retention_bounds_equal(
      evidence.retention,
      publication_retention,
    ) {
    return Err(Relation(@publication.WrongRetention))
  }
  let invocation = match
    issue_client_effect_local_invocation_body(
      owner,
      unit,
      definition,
      values,
      contracts,
      @checked.checked_local_policy_cid(program),
      [@publication.run_evidence_value_identity(evidence.observation)],
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  // Pure terminal fence, not another current callback or a revived holding.
  if lookup.closed ||
    lookup.left.lookup_issue is Some(_) ||
    !(lookup.native_sources is Some(same) && physical_equal(same, state)) {
    return Err(Invocation(ForeignCapturedInput))
  }
  Ok({
    owner,
    identity: evidence.identity,
    captured,
    purpose: SingleSourceUnit,
    invocation,
    input: evidence.logical,
    observation: evidence.observation,
    request: evidence.request,
    request_cid: evidence.request_cid,
    retention: evidence.retention,
    publication_retention,
    relation: evidence.relation,
    ordering: evidence.ordering,
    scope: evidence.scope,
  })
}
