///|
fn client_effect_keyed_generic_completed(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  state : ClientEffectKeyedGenericState,
) -> Bool {
  physical_equal(state.lookup, lookup) &&
  parent.generic is Some(same) &&
  physical_equal(same, state) &&
  state.completed is Some(_) &&
  state.bodies is Some(_) &&
  lookup.identity is Some(_) &&
  lookup.read is Some(read) &&
  lookup.holding is Some(holding) &&
  @resources.holding_available(parent.ledger, holding) &&
  client_effect_keyed_lookup_matches_parent(lookup, parent, parent.ledger) &&
  @execution.supplied_relation_read_available(read)
}

///|
fn prepare_client_effect_generic_keyed_source_unit(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  state : ClientEffectKeyedGenericState,
  host : @strategy.CapturedEffectRunDAG,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[ClientEffectKeyedSourceUnit, ClientEffectAcquiredEvidenceIssue] {
  guard client_effect_keyed_source_host_matches(parent, lookup, host) &&
    state.completed is Some(completed) &&
    @publication.result_retention_bounds_equal(completed.retention, retention) &&
    @publication.result_retention_bounds_equal(
      state.source.retention,
      retention,
    ) &&
    client_keyed_acquisition_coordinates(parent.keyed) is Some((unit, _, _)) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let program = @checked.effect_program_static_checked_computation(
    parent.prepared.candidate,
  )
  guard @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) else {
    return Err(Invocation(MissingUnit))
  }
  let observations = [
    @publication.run_evidence_value_identity(state.source.observation),
    @publication.run_evidence_value_identity(completed.observation.source),
  ]
  let scope = match
    @publication.issue_combined_acquisition_scope(
      [state.source.scope, completed.scope],
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  let invocation = match
    issue_client_local_unit_invocation(
      parent.prepared,
      unit,
      definition,
      values,
      contracts,
      @checked.checked_local_policy_cid(program),
      observations,
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let relations = [
    @publication.publication_contract_identity(state.source.relation),
    @publication.publication_contract_identity(completed.relation),
  ]
  relations.sort_by(@canonical_value.compare_utf16)
  guard client_effect_keyed_source_host_matches(parent, lookup, host) &&
    state.completed is Some(same) &&
    physical_equal(same, completed) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  Ok({
    parent,
    lookup,
    completed: GenericSourceCompleted(completed),
    host,
    invocation,
    scope,
    relations,
    retention,
  })
}

///|
// Return the existing private Option/Array themselves after ONE current
// boundary. This neither reexports/admit DATA nor turns cache presence into ACK.
fn client_effect_keyed_generic_cached_dependency_bodies(
  parent : ClientEffectKeyedOriginal,
  lookup : ClientKeyedLookupInput,
  state : ClientEffectKeyedGenericState,
  retention : @publication.PublicationContract,
) -> Array[@publication.CapturedEffectDependencyBody]? {
  guard !lookup.closed &&
    !lookup.growing &&
    !lookup.identifying &&
    lookup.left.lookup_issue is None &&
    state.bodies is Some(bodies) &&
    state.completed is Some(completed) &&
    @publication.result_retention_bounds_equal(state.retention, retention) &&
    client_effect_keyed_generic_completed(parent, lookup, state) else {
    return None
  }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    parent.generic is Some(same_state) &&
    physical_equal(same_state, state) &&
    state.completed is Some(same) &&
    physical_equal(same, completed) &&
    state.bodies is Some(same_bodies) &&
    physical_equal(same_bodies, bodies) else {
    return None
  }
  state.bodies
}
