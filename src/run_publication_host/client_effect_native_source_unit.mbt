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

///|
/// Bind a distinct completed whole-Source Unit from its ORIGINAL capture tuple.
/// This is the whole-input counterpart of the keyed entrance above. It does
/// not accept ModelContribution, infer a producer from names, or grant a read.
/// The caller retains the real Source and backs all bounded metadata first.
pub fn issue_client_whole_native_effect_source_unit(
  owner : PreparedClientEffectComputation,
  direct : ClientDirectAcquisitionOccurrences,
  index : Int,
  captured : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  acquisition : @acquisition.SourceAcquisition,
  input : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  publication_retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectAcquiredEvidence, ClientEffectAcquiredEvidenceIssue] {
  guard client_direct_acquisition_occurrences_match_effect_program(
      direct, owner,
    ) &&
    client_direct_acquisition_occurrence_at(direct, index)
    is Some((unit, ordinal, task)) &&
    client_source_acquisition_matches_effect_program(
      owner, unit, ordinal, acquisition,
    ) &&
    @query.captured_source_matches_input_acquisition(captured, acquisition) &&
    @query.captured_source_relation_identity_matches_source(identity, captured) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  let mut producers = 0
  for entry in direct.coordinates {
    if entry.0 == unit {
      producers += 1
    }
  }
  guard task == unit &&
    unit < @strategy.graph_captured_prefix(graph) &&
    // One complete producer, not one contribution to a multi-Source Unit.
    producers == 1 &&
    @strategy.graph_task_owner(graph, task) is Some(original) &&
    @query.captured_source_matches(
      captured,
      @checked.source_identity(@strategy.graph_program(graph)),
      original,
    ) &&
    @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_pipeline(program, unit) is Some(pipeline) &&
    client_effect_source_unit_without_model(pipeline) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) &&
    @planning.source_acquisition_evidence_facts(acquisition) is Some(facts) else {
    return Err(Invocation(MissingUnit))
  }
  if @publication.admit_completed_source_input_logical(
      input,
      @query.captured_source_relation_logical_cid(identity),
      @query.captured_source_relation_schema_cid(identity),
      facts.source_contract_cid,
      "{\"stable\":false,\"keys\":[]}",
      max_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) ||
    @publication.admit_completed_source_observation_binding(
      observation,
      input,
      facts.source_ref,
      facts.source_contract_cid,
      authority_scope_cid,
      facts.source_data_policy_cid,
      max_bytes,
      max_nodes,
      max_depth,
    )
    is Err(_) {
    return Err(Invocation(ForeignSourceObservation))
  }
  let (request, request_cid) = match
    client_effect_whole_source_request_material(
      acquisition, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let retention = match
    @publication.issue_result_retention_for_data_policy(
      publication_retention,
      facts.source_data_policy_cid,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(@publication.Contract(issue)))
  }
  let (relation, ordering, scope) = match
    @publication.issue_captured_source_input_relation(
      input,
      observation,
      request_cid,
      @query.captured_source_relation_row_count(identity),
      retention,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  let invocation = match
    issue_client_effect_local_invocation_body(
      owner,
      unit,
      definition,
      values,
      contracts,
      @checked.checked_local_policy_cid(program),
      [@publication.run_evidence_value_identity(observation)],
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  // Request emission may observe an original Ref. Do not return an artifact
  // after that callback has retired or replaced the captured input.
  if !@query.captured_source_available(captured) {
    return Err(Invocation(ForeignCapturedInput))
  }
  Ok({
    owner,
    identity,
    captured,
    purpose: SingleSourceUnit,
    invocation,
    input,
    observation,
    request,
    request_cid,
    retention,
    publication_retention,
    relation,
    ordering,
    scope,
  })
}

///|
// An input is not the complete provenance of an inline Model Unit. Inspect
// only the original immutable checked operations, not text or a new checker.
fn client_effect_source_unit_without_model(
  pipeline : @pipeline.CheckedPipeline,
) -> Bool {
  for step in 0..<@pipeline.step_count(pipeline) {
    if @pipeline.step_at(pipeline, step) is Some(original) &&
      original.operation is @pipeline.Infer(_) {
      return false
    }
  }
  true
}

///|
// One publication preimage for all Whole Source contribution/Unit issuers.
// The original RowRun reserves its field-reference scratch before capture;
// explicit semantic callers must back that same scratch before entering here.
// A writer is synchronous, so its temporary array is gone before the next one.
// Transport spelling and the original Request/binding indices stay unchanged.
fn client_effect_whole_source_request_material(
  acquisition : @acquisition.SourceAcquisition,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(@encode.EncodedDocument, String), ClientEffectLocalInvocationIssue] {
  @acquisition.parameterized_request_canonical_document(
    @acquisition.source_acquisition_request(acquisition),
    max_bytes,
    max_nodes,
    max_depth,
  )
  .map_err(_ => ClientEffectLocalInvocationIssue::Encoding)
  .bind(document => {
    @sha.text_hex(@encode.document_text(document))
    .map(hash => (document, "sha256:" + hash))
    .map_err(_ => ClientEffectLocalInvocationIssue::Encoding)
  })
}
