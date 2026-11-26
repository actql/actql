///|
/// Closed Source provenance of a completed Local Unit. Every Result on this
/// unit uses a separately checked producer policy and its live export receipt.
struct ClientWholeLocalUnitPublication {
  invocation : ClientWholeLocalUnitInvocation
  retention : @publication.PublicationContract
  contributions : Array[ClientLocalSourceUnitContribution]
  scope : @publication.PublicationContract
  relations : Array[String]
}

///|
pub type ClientWholeLocalResultArtifact = ClientLocalResultArtifact[
  ClientWholeLocalUnitOriginal,
  ClientLocalUnitResultDefinition[ClientWholeLocalUnitOriginal],
  @strategy.CapturedCompletedUnitResultHandoff,
]

///|
/// Prepare Source metadata once from the ordered, authorized originals of the
/// same Unit. Fund each codec geometry before constructing the metadata bodies.
pub fn prepare_client_whole_local_unit_publication(
  invocation : ClientWholeLocalUnitInvocation,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fund_controls : (Int) -> Bool,
  fund_body : (String, @encode.EncodingConstructionGeometry) -> Bool,
) -> Result[ClientWholeLocalUnitPublication, ClientEffectAcquiredEvidenceIssue] {
  let owner = invocation.owner
  let sources = owner.sources.inputs
  let count = sources.length()
  if !client_whole_local_unit_original_live(owner) ||
    count <= 0 ||
    count > max_nodes {
    return Err(Invocation(ForeignCapturedInput))
  }
  if !fund_controls(count) ||
    !client_whole_local_unit_original_live(owner) ||
    !client_infer_composed_whole_sources_match_run(
      owner.sources,
      owner.run,
      after_completion=true,
    ) {
    return Err(Invocation(ForeignCapturedInput))
  }
  let observations = Array(capacity=count)
  let inputs = Array(capacity=count)
  let rows = Array(capacity=count)
  for input in sources {
    guard input.original is Whole(acquisition) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    let request = @acquisition.source_acquisition_request(acquisition)
    let geometry = match
      @acquisition.parameterized_request_canonical_geometry(
        request, max_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(Invocation(Encoding))
    }
    if !fund_body("request_values", geometry) {
      return Err(Invocation(Encoding))
    }
    let (source, logical, _, _) = @publication.model_source_observation_originals(
      input.observation,
    )
    observations.push(source)
    inputs.push(logical)
    rows.push(@query.captured_source_relation_row_count(input.identity))
  }
  let metadata = match
    @publication.source_unit_metadata_construction_geometry(
      observations,
      inputs,
      rows,
      retention,
      max_bytes,
      max_nodes,
      max_depth,
      include_union=count > 1,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  for (name, geometry) in metadata {
    if !fund_body(name, geometry) {
      return Err(Invocation(Encoding))
    }
  }
  if !client_whole_local_unit_original_live(owner) ||
    !client_infer_composed_whole_sources_match_run(
      owner.sources,
      owner.run,
      after_completion=true,
    ) {
    return Err(Invocation(ForeignCapturedInput))
  }
  let contributions = Array(capacity=count)
  let scopes = Array(capacity=count)
  let relations = Array(capacity=count)
  for index, input in sources {
    guard input.original is Whole(acquisition) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    let part = match
      prepare_client_local_source_unit_contribution(
        index,
        WholeSourceOriginal(acquisition),
        inputs[index],
        observations[index],
        input.identity,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    contributions.push(part)
    scopes.push(part.scope)
    let relation = @publication.publication_contract_identity(part.relation)
    if !relations.contains(relation) {
      relations.push(relation)
    }
  }
  relations.sort_by(@canonical_value.compare_utf16)
  let scope = if count == 1 {
    scopes[0]
  } else {
    match
      @publication.issue_combined_acquisition_scope(
        scopes, max_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
  }
  Ok({ invocation, retention, contributions, scope, relations, })
}

///|
/// Check that all retained Source contributions belong to this exact Result.
/// Measure the bounded match against the same checked Result policy inventory.
fn client_whole_local_result_policy_cid(
  value : ClientWholeLocalUnitPublication,
  port : @results.ResultPort,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientEffectLocalResultArtifactIssue] {
  let original = value.invocation.owner
  let program = @strategy.graph_program(
    original.scope.origin.compiled.owner.graph,
  )
  let count = value.contributions.length().to_int64()
  let checks = count * count
  if checks > max_work.to_int64() {
    return Err(ForeignDefinition)
  }
  let selected = @checked.prepare_local_result_source_policy(
    program,
    original.unit,
    port,
    max_work - checks.to_int(),
    max_bytes,
    max_nodes,
    max_depth,
  ) catch {
    _ => return Err(ForeignDefinition)
  }
  guard selected is Some(policy) &&
    @checked.publication_policy_source_count(policy) ==
    value.contributions.length() &&
    @checked.publication_policy_model_step_count(policy) == 0 else {
    return Err(ForeignDefinition)
  }
  for part in value.contributions {
    let input = original.sources.inputs[part.slot]
    let mut matches = 0
    for index in 0..<value.contributions.length() {
      let source = @checked.publication_policy_source_at(policy, index).unwrap()
      if model_effect_source_original_matches_check(input.original, source) {
        matches += 1
      }
    }
    if matches != 1 {
      return Err(ForeignDefinition)
    }
  }
  Ok(policy.cid)
}

///|
/// Issue the existing local Artifact form from the exact checked Unit export.
/// The corresponding completed Result, Source evidence and Run remain held.
pub fn issue_client_whole_local_result_artifact(
  value : ClientWholeLocalUnitPublication,
  index : Int,
  handoff : @strategy.CapturedCompletedUnitResultHandoff,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fund_controls : () -> Bool,
  fund_body : (String, @encode.EncodingConstructionGeometry) -> Bool,
) -> Result[
  ClientWholeLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  let invocation = value.invocation
  let owner = invocation.owner
  guard client_whole_local_unit_original_live(owner) &&
    @strategy.captured_completed_unit_result_export_original(
      handoff,
      owner.results,
      index,
    )
    is Some((port, receipt)) else {
    return Err(ForeignExport)
  }
  if !fund_controls() ||
    !client_whole_local_unit_original_live(owner) ||
    @strategy.captured_completed_unit_result_export_original(
      handoff,
      owner.results,
      index,
    )
    is None {
    return Err(ForeignExport)
  }
  let result_name = @results.name(@results.port_result(port))
  let policy = match
    client_whole_local_result_policy_cid(
      value, port, max_work, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @publication.result_retention_policy_construction_geometry(
      value.retention,
      policy,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(Some(geometry)) =>
      if !fund_body("result_retention_policy", geometry) {
        return Err(ForeignExport)
      }
    Ok(None) => ()
    Err(issue) => return Err(Scope(issue))
  }
  let retention = match
    @publication.issue_result_retention_for_data_policy(
      value.retention,
      policy,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Scope(issue))
  }
  let definition_measure = @encode.construction_measuring_writer(
    max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(ForeignDefinition)
  }
  let definition_shape = try {
    emit_client_effect_local_result_definition(
      definition_measure,
      invocation.unit_definition_cid,
      result_name,
      Some(invocation.unit_definition_cid),
    )
    @encode.finish_construction_measurement(definition_measure)
  } catch {
    _ => {
      @encode.cancel_writer(definition_measure)
      return Err(ForeignDefinition)
    }
  }
  let ancestry = @publication.run_publication_execution_context(
    owner.scope.origin.compiled.admission,
  )
  let scope = @publication.publication_contract_identity(value.scope)
  let shapes = match
    @publication.local_result_metadata_construction_geometry(
      invocation.unit_definition_cid,
      invocation.cid,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
      invocation.unit_definition_cid,
      value.relations,
      scope,
      policy,
      "actql-common-host",
      ancestry,
      @publication.publication_contract_identity(retention),
      @execution.completed_relation_export_scalar_geometry(receipt).2,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  if !fund_body("local_result_definition", definition_shape) ||
    !fund_body("derivation_evidence", shapes[0]) ||
    !fund_body("ordering_evidence", shapes[1]) ||
    !fund_body("result_artifact", shapes[2]) ||
    !client_whole_local_unit_original_live(owner) ||
    !client_infer_composed_whole_sources_match_run(
      owner.sources,
      owner.run,
      after_completion=true,
    ) ||
    @strategy.captured_completed_unit_result_export_original(
      handoff,
      owner.results,
      index,
    )
    is None {
    return Err(ForeignExport)
  }
  let definition = match
    issue_client_local_unit_result_definition(
      owner,
      invocation.unit,
      invocation.unit_definition_cid,
      result_name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignDefinition)
  }
  build_client_local_result_artifact(
    handoff,
    definition,
    invocation,
    receipt,
    None,
    retention,
    definition.cid,
    invocation.unit_definition_cid,
    scope,
    policy,
    ancestry,
    value.relations,
    max_bytes,
    max_nodes,
    max_depth,
    scope=Some(value.scope),
  )
}
