///|
pub(all) enum ClientEffectAcquiredEvidenceIssue {
  Invocation(ClientEffectLocalInvocationIssue)
  Relation(@publication.AcquisitionRelationIssue)
  Dependency(@checked.LocalDependencyBodyIssue)
} derive(Eq, Debug)

///|
// The old single-Source Artifact entry must not accept an individual Source
// contribution from the new multi-input Model closure as an entire Unit.
priv enum ClientEffectSourceEvidencePurpose {
  SingleSourceUnit
  ModelContribution
}

///|
/// Closed source provenance from the actual common capture and checked
/// static request. This does not grant a mutation or transfer Store custody.
struct ClientEffectAcquiredEvidence {
  owner : PreparedClientEffectComputation
  identity : @query.CapturedSourceRelationIdentity
  captured : @query.CapturedInputSource
  purpose : ClientEffectSourceEvidencePurpose
  invocation : ClientEffectLocalInvocation
  input : @publication.RunEvidenceValue
  observation : @publication.RunEvidenceValue
  request : @encode.EncodedDocument
  request_cid : String
  retention : @publication.PublicationContract
  publication_retention : @publication.PublicationContract
  relation : @publication.PublicationContract
  ordering : @publication.PublicationContract
  scope : @publication.PublicationContract
}

///|
/// The exact Source observation chooses its Catalog closure. Environment
/// bodies are not accepted from the adapter and no new acquisition occurs.
pub fn client_effect_acquired_catalog_bodies(
  value : ClientEffectAcquiredEvidence,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(String, String, String)], ClientEffectAcquiredEvidenceIssue] {
  let references = match
    @publication.source_effect_catalog_dependencies(value.observation) {
    Ok(refs) => refs
    Err(_) => return Err(Dependency(MissingDependency))
  }
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(value.owner),
  )
  let bodies = []
  let seen : Map[String, Bool] = Map([])
  let mut remaining = Int::min(max_bytes, 16777216)
  for (role, cid) in references {
    let key = role + "\u0000" + cid
    if seen.contains(key) {
      continue
    }
    let body = match
      @checked.checked_local_catalog_dependency_body(
        program,
        value.invocation.unit,
        role,
        cid,
        remaining,
        max_nodes,
        max_depth,
      ) {
      Ok(body) => body
      Err(issue) => return Err(Dependency(issue))
    }
    let wire = @checked.checked_local_dependency_body_json(body)
    remaining -= @utf8.encode(wire).length()
    bodies.push((role, @checked.checked_local_dependency_body_cid(body), wire))
    seen[key] = true
  }
  Ok(bodies)
}

///|
pub fn client_effect_acquired_invocation(
  value : ClientEffectAcquiredEvidence,
) -> ClientEffectLocalInvocation {
  value.invocation
}

///|
/// The Source observation was admitted with the exact live acquisition. It is
/// an immutable dependency fact, not permission to repeat the original read.
pub fn client_effect_acquired_observation(
  value : ClientEffectAcquiredEvidence,
) -> @publication.RunEvidenceValue {
  value.observation
}

///|
pub fn issue_client_effect_acquired_evidence(
  owner : PreparedClientEffectComputation,
  captured : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  input : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  authority_scope_cid : String,
  data_policy_cid : String,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  unit? : Int = 0,
  publication_retention? : @publication.PublicationContract? = None,
) -> Result[ClientEffectAcquiredEvidence, ClientEffectAcquiredEvidenceIssue] {
  let publication_retention = publication_retention.unwrap_or(retention)
  if !@publication.result_retention_bounds_equal(
      retention, publication_retention,
    ) {
    return Err(Relation(@publication.WrongRetention))
  }
  let invocation = match
    issue_acquired_client_effect_local_invocation(
      owner,
      captured,
      identity,
      requirement,
      input,
      observation,
      authority_scope_cid,
      data_policy_cid,
      max_bytes,
      max_nodes,
      max_depth,
      unit~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let material = @planning.query_requirement_material(requirement)
  let (request_cid, _, _) = @planning.query_material_cids(material)
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
  Ok({
    owner,
    identity,
    captured,
    purpose: SingleSourceUnit,
    invocation,
    input,
    observation,
    request: @planning.query_material_request(material),
    request_cid,
    retention,
    publication_retention,
    relation,
    ordering,
    scope,
  })
}

///|
pub fn client_effect_acquired_request_cid(
  value : ClientEffectAcquiredEvidence,
) -> String {
  value.request_cid
}

///|
/// All required source bodies remain available for the bounded dependency
/// inventory. Returning them does not waive its aggregate-byte admission.
pub fn client_effect_acquired_dependency_bodies(
  value : ClientEffectAcquiredEvidence,
) -> Array[(String, String)] {
  let bodies = [
    ("source_input_logical", @publication.run_evidence_value_json(value.input)),
    ("source_evidence", @publication.run_evidence_value_json(value.observation)),
    ("request_values", @encode.document_text(value.request)),
    (
      "acquisition_relation",
      @publication.publication_contract_json(value.relation),
    ),
    (
      "ordering_evidence",
      @publication.publication_contract_json(value.ordering),
    ),
    ("acquisition_scope", @publication.publication_contract_json(value.scope)),
  ]
  if @publication.publication_contract_identity(value.retention) !=
    @publication.publication_contract_identity(value.publication_retention) {
    bodies.push(
      (
        "result_retention_policy",
        @publication.publication_contract_json(value.retention),
      ),
    )
  }
  bodies
}

///|
// The Source completion and a later computed Result are different physical
// outputs. The immutable acquisition evidence already belongs to this SAME
// checked Unit; its computed Result must instead present the exact checked
// producer/Target. The caller separately requires its live original export
// receipt and Run admission. This does not turn the result into a Source pin.
fn client_effect_computed_result_matches_acquired_unit(
  owner : PreparedClientEffectComputation,
  source : ClientEffectAcquiredEvidence,
  result : @strategy.CapturedEffectLocalResult,
) -> Bool {
  let graph = @strategy.checked_effect_computation_graph(owner.graph)
  let unit = @strategy.captured_effect_local_result_stage(result)
  let task = @strategy.captured_effect_local_result_task(result)
  if !physical_equal(source.owner, owner) ||
    unit != source.invocation.unit ||
    unit < 0 ||
    unit >= @strategy.graph_captured_prefix(graph) ||
    task < @strategy.graph_captured_prefix(graph) {
    return false
  }
  let occurrence = @strategy.captured_any_result_borrow_occurrence(
    @strategy.captured_effect_local_result_borrow(result),
  )
  @strategy.graph_stage_target_task(
    graph,
    unit,
    @results.port_target(@execution.managed_result_occurrence_port(occurrence)),
  ) ==
  Some(task)
}

///|
pub fn issue_acquired_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  source : ClientEffectAcquiredEvidence,
  definition : ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  let result = @strategy.captured_effect_local_result_export_result(exported)
  if !physical_equal(source.owner, owner) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    (
      !@strategy.captured_effect_local_result_matches_source(
        inputs,
        result,
        source.identity,
      ) &&
      !(client_effect_computed_result_matches_acquired_unit(
        owner, source, result,
      ) &&
      @strategy.captured_effect_inputs_acquired_source_matches(
        inputs,
        source.invocation.unit,
        source.identity,
      ))
    ) {
    return Err(ForeignOwner)
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(ForeignExport)
  }
  build_client_effect_acquired_result_artifact(
    EffectInputs(inputs),
    owner,
    @strategy.captured_effect_local_result_borrow(result),
    source,
    definition,
    receipt,
    admission,
    run_definition,
    run_invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn build_client_effect_acquired_result_artifact(
  custody : ClientEffectLocalArtifactCustody,
  owner : PreparedClientEffectComputation,
  borrow : @strategy.CapturedAnyResultBorrow,
  source : ClientEffectAcquiredEvidence,
  definition : ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  run_invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  if source.purpose is ModelContribution {
    return Err(ForeignOwner)
  }
  if !client_effect_local_result_definition_matches(
      definition,
      owner,
      source.invocation.unit,
      @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(borrow),
      ),
    ) {
    return Err(ForeignDefinition)
  }
  if client_effect_local_custody_run_definition_cid(custody) !=
    Some(@publication.publication_contract_identity(run_definition)) ||
    @publication.check_run_publication_program_binding(
      admission,
      run_definition,
      prepared_client_effect_computation_definition_cid(owner),
      prepared_client_effect_computation_semantics_cid(owner),
      prepared_client_effect_computation_environment_cid(owner),
    )
    is Err(_) {
    return Err(ForeignRun)
  }
  let (_, policy, authority) = match
    @publication.resolve_run_local_result_evidence_refs(
      admission,
      run_definition,
      run_invocation,
      observation,
      source.publication_retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  build_client_effect_local_result_artifact(
    custody,
    ResultSource(borrow, definition),
    source.invocation,
    receipt,
    run_invocation,
    source.publication_retention,
    @publication.publication_contract_identity(source.scope),
    policy,
    authority,
    [@publication.publication_contract_identity(source.relation)],
    max_bytes,
    max_nodes,
    max_depth,
    scope=Some(source.scope),
  )
}

///|
/// Read the preimages retained by this exact original Source identity pass.
/// Keep this explicit currentful body borrow separate from the immutable
/// metadata dependency getter. It performs no re-export/hash/provider read.
/// Missing bodies or retired originals stay absent; they are never rebuilt.
pub fn client_effect_acquired_relation_dependency_bodies(
  value : ClientEffectAcquiredEvidence,
) -> Array[(String, String)]? {
  @query.captured_source_relation_dependency_bodies(
    value.identity,
    value.captured,
  ).map(body => [("relation_value", body.0), ("relation_schema", body.1)])
}
