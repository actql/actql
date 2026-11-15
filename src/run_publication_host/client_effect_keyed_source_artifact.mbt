///|
/// Artifact from the actual completed Source-only keyed Unit. The canonical
/// receipt and checked producer Result are independent of its Source inputs.
pub fn issue_keyed_source_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : ClientEffectKeyedSourceUnit,
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
  build_keyed_source_client_effect_local_result_artifact(
    owner,
    EffectInputs(inputs),
    exported,
    acquired,
    definition,
    receipt,
    admission,
    run_definition,
    Some((run_invocation, observation)),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
pub fn issue_keyed_source_client_effect_unit_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : ClientEffectKeyedSourceUnit,
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
  build_keyed_source_client_effect_local_result_artifact(
    owner,
    AcquiredUnit(inputs),
    exported,
    acquired,
    definition,
    receipt,
    admission,
    run_definition,
    Some((run_invocation, observation)),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn build_keyed_source_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  custody : ClientEffectLocalArtifactCustody,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : ClientEffectKeyedSourceUnit,
  definition : ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  final_context : (
    @publication.PublicationContract,
    @publication.RunEvidenceValue,
  )?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  let invocation = acquired.invocation
  let result = @strategy.captured_effect_local_result_export_result(exported)
  if !physical_equal(invocation.owner, owner) ||
    !(match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_inputs_match_computation(inputs, owner.graph)
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_inputs_match_computation(
          inputs,
          owner.graph,
        )
    }) ||
    !client_effect_computed_result_matches_invocation(
      owner, invocation, exported,
    ) {
    return Err(ForeignOwner)
  }
  // Keep the original check order and availability callbacks. These are
  // distinct failures: stale Source invocation, another Run's input custody,
  // and a foreign export receipt must not collapse into one opaque issue.
  if !client_effect_keyed_source_unit_current(acquired) {
    return Err(ForeignInvocation)
  }
  if !(match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_inputs_match_run(inputs, acquired.host)
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_inputs_match_run(
          inputs,
          acquired.host,
        )
    }) {
    return Err(ForeignRun)
  }
  if !(match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        )
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_result_export_matches_receipt(
          inputs, exported, receipt,
        )
    }) {
    return Err(ForeignExport)
  }
  let borrow = @strategy.captured_effect_local_result_borrow(result)
  if !client_effect_local_result_definition_matches(
      definition,
      owner,
      invocation.unit,
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
  let (run_invocation, policy, authority) = match final_context {
    Some((invocation, observation)) => {
      let (_, policy, authority) = match
        @publication.resolve_run_local_result_context(
          admission, run_definition, invocation, observation,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Context(issue))
      }
      (Some(invocation), policy, authority)
    }
    None => {
      guard custody is AcquiredUnit(_) &&
        prepared_client_effect_publication_data_policy_cid(owner)
        is Some(policy) else {
        return Err(ForeignOwner)
      }
      (None, policy, @publication.run_publication_execution_context(admission))
    }
  }
  let retention = match
    @publication.issue_result_retention_for_data_policy(
      acquired.retention,
      policy,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Scope(issue))
  }
  let relations = acquired.relations
  build_client_effect_local_result_artifact(
    custody,
    ResultSource(borrow, definition),
    invocation,
    receipt,
    run_invocation,
    retention,
    @publication.publication_contract_identity(acquired.scope),
    policy,
    authority,
    relations,
    max_bytes,
    max_nodes,
    max_depth,
    scope=Some(acquired.scope),
  )
}

///|
pub fn client_effect_keyed_source_public_result_evidence_refs(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  acquired : ClientEffectKeyedSourceUnit,
  artifact : ClientEffectLocalResultArtifact,
  result : Int,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
) -> Result[
  (String, Array[String], String, String, String),
  ClientEffectLocalResultArtifactIssue,
] {
  if !client_effect_keyed_source_unit_current(acquired) ||
    !@strategy.captured_effect_inputs_match_run(inputs, acquired.host) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !physical_equal(materials.compilation.owner, materials.prepared) ||
    !physical_equal(acquired.invocation.owner, materials.prepared) ||
    !physical_equal(artifact.invocation, acquired.invocation) ||
    !(acquired.parent.compiled.compilation is Effects(allowed) &&
    physical_equal(allowed, materials.allowed)) ||
    !client_effect_local_artifact_matches_computation(
      artifact,
      materials.prepared,
    ) ||
    !client_effect_local_artifact_matches_inputs(artifact, inputs) {
    return Err(ForeignOwner)
  }
  guard artifact.source is ResultSource(_, definition) &&
    effect_local_result_definition_matches_public_result(
      materials.prepared,
      definition,
      result,
    ) else {
    return Err(ForeignDefinition)
  }
  if client_effect_local_artifact_run_definition_cid(artifact) !=
    Some(@publication.publication_contract_identity(materials.run_definition)) ||
    client_effect_local_artifact_run_invocation_cid(artifact) !=
    Some(@publication.publication_contract_identity(invocation)) {
    return Err(ForeignRun)
  }
  let (_, policy, authority) = match
    @publication.resolve_run_local_result_evidence_refs(
      materials.allowed.admission,
      materials.run_definition,
      invocation,
      observation,
      artifact.retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  let relations = acquired.relations
  Ok(
    (
      @publication.publication_contract_identity(
        client_effect_compilation_compiled_plan(materials.compilation),
      ),
      relations,
      @publication.publication_contract_identity(acquired.scope),
      policy,
      authority,
    ),
  )
}

///|
pub fn client_effect_keyed_source_unit_artifact_construction_geometry(
  owner : PreparedClientEffectComputation,
  acquired : ClientEffectKeyedSourceUnit,
  result_name : String,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, @encode.EncodingConstructionGeometry)],
  ClientEffectLocalResultArtifactIssue,
] {
  guard physical_equal(acquired.invocation.owner, owner) &&
    prepared_client_effect_publication_data_policy_cid(owner) is Some(policy) else {
    return Err(ForeignOwner)
  }
  let definition = match
    client_effect_local_result_definition_construction_geometry(
      owner,
      acquired.invocation.unit,
      result_name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignDefinition)
  }
  let relations = acquired.relations
  let retention = match
    @publication.result_retention_policy_construction_geometry(
      acquired.retention,
      policy,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Scope(issue))
  }
  let shapes = match
    @publication.local_result_metadata_construction_geometry(
      acquired.invocation.unit_definition_cid,
      acquired.invocation.cid,
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
      acquired.invocation.unit_definition_cid,
      relations,
      @publication.publication_contract_identity(acquired.scope),
      policy,
      "actql-common-host",
      @publication.run_publication_execution_context(admission),
      @publication.publication_contract_identity(acquired.retention),
      @execution.completed_relation_export_measurement(receipt).row_count,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let bodies = [
    ("local_result_definition", definition),
    ("derivation_evidence", shapes[0]),
    ("ordering_evidence", shapes[1]),
    ("result_artifact", shapes[2]),
  ]
  if retention is Some(shape) {
    bodies.push(("result_retention_policy", shape))
  }
  Ok(bodies)
}
