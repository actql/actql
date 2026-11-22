///|
pub(all) enum ClientEffectImportedEvidenceIssue {
  Invocation(ClientEffectLocalInvocationIssue)
  MissingScope
  IncompatibleScope
  Relation(@publication.AcquisitionRelationIssue)
} derive(Eq, Debug)

///|
/// Dependency edges originate in actual retained import observations. This
/// owner carries their bodies until Store custody is established.
struct ClientEffectImportedEvidence {
  owner : PreparedClientEffectComputation
  inputs : @strategy.CapturedEffectInputs
  invocation : ClientEffectLocalInvocation
  observations : Array[ClientEffectResultImportObservation]
  relations : Array[@publication.PublicationContract]
  scope : @publication.PublicationContract
}

///|
pub fn issue_client_effect_imported_evidence(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  unit : Int,
  observations : Array[ClientEffectResultImportObservation],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectImportedEvidence, ClientEffectImportedEvidenceIssue] {
  let invocation = match
    issue_imported_client_effect_local_invocation(
      owner, inputs, unit, observations, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  // Retain each producer's exact scope on its Relation. The downstream
  // scope is the canonical request inventory of those captured imports,
  // not a union of access permissions or a caller-supplied source list.
  let scopes : Array[@publication.PublicationContract] = []
  let relations : Array[@publication.PublicationContract] = []
  for observation in observations {
    let artifact = observation.artifact
    guard artifact.scope is Some(input_scope) else { return Err(MissingScope) }
    scopes.push(input_scope)
    let relation = match
      @publication.issue_derived_input_relation(
        artifact.artifact,
        artifact.evidence,
        input_scope,
        artifact.retention,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
    // Repeated imports retain their separate observation positions. The
    // Derivation's Relation dependency set itself has no duplicate CIDs.
    if !relations.any(value => {
        @publication.publication_contract_identity(value) ==
        @publication.publication_contract_identity(relation)
      }) {
      relations.push(relation)
    }
  }
  let scope = match
    @publication.issue_combined_acquisition_scope(
      scopes, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  relations.sort_by(fn(a, b) {
    @canonical_value.compare_utf16(
      @publication.publication_contract_identity(a),
      @publication.publication_contract_identity(b),
    )
  })
  Ok({
    owner,
    inputs,
    invocation,
    observations: observations.copy(),
    relations,
    scope,
  })
}

///|
pub fn client_effect_imported_invocation(
  value : ClientEffectImportedEvidence,
) -> ClientEffectLocalInvocation {
  value.invocation
}

///|
/// The derived Result references this exact combined scope. Retain its body
/// alongside the input Relations so recovery can close the evidence graph.
pub fn client_effect_imported_scope_json(
  value : ClientEffectImportedEvidence,
) -> String {
  @publication.publication_contract_json(value.scope)
}

///|
pub fn client_effect_imported_relation_bodies(
  value : ClientEffectImportedEvidence,
) -> Array[String] {
  value.relations.map(@publication.publication_contract_json)
}

///|
/// Measure the already issued evidence while its original construction
/// owner holds the codec peak and funds one depth-bounded extent walk.
/// Include only the new holder, its arrays, invocation, scope and Relations.
/// Each observation element and the checked owner/inputs are original borrows.
pub fn client_effect_imported_evidence_retained_bytes(
  value : ClientEffectImportedEvidence,
  max_nodes : Int,
  max_depth : Int,
) -> Int64? {
  guard @shape.reference_array_retained_extent(
      2L,
      value.observations.capacity().to_int64() +
      value.relations.capacity().to_int64(),
    )
    is Some(arrays) &&
    @execution.preparation_representation_cost({
      // Evidence (6 refs), invocation (4 refs and the Unit coordinate),
      // and the invocation's two owned Strings. The Unit CID is borrowed.
      record_headers: 4L + arrays.record_headers,
      reference_slots: 10L + arrays.reference_slots,
      scalar_words: 1L + arrays.scalar_words,
      owned_utf16_units: value.invocation.cid.length().to_int64() +
      value.invocation.wire.length().to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    local_effect_contract_retained_bytes(value.scope, max_nodes, max_depth)
    is Some(scope) &&
    @execution.checked_preparation_add_product(controls, scope, 1L)
    is Some(base) else {
    return None
  }
  let mut retained = base
  for relation in value.relations {
    guard local_effect_contract_retained_bytes(relation, max_nodes, max_depth)
      is Some(bytes) &&
      @execution.checked_preparation_add_product(retained, bytes, 1L)
      is Some(total) else {
      return None
    }
    retained = total
  }
  Some(retained)
}

///|
pub fn issue_imported_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  imported : ClientEffectImportedEvidence,
  definition : ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
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
  if !client_effect_imported_evidence_matches_owner(imported, owner, inputs) {
    return Err(ForeignOwner)
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(ForeignExport)
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let borrow = @strategy.captured_effect_local_result_borrow(result)
  if @strategy.captured_effect_local_result_stage(result) !=
    imported.invocation.unit ||
    !client_effect_local_result_definition_matches(
      definition,
      owner,
      imported.invocation.unit,
      @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(borrow),
      ),
    ) {
    return Err(ForeignDefinition)
  }
  if @strategy.captured_effect_inputs_run_definition_cid(inputs) !=
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
      admission, run_definition, run_invocation, observation, retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  build_client_effect_local_result_artifact(
    EffectInputs(inputs),
    ResultSource(borrow, definition),
    imported.invocation,
    receipt,
    Some(run_invocation),
    retention,
    @publication.publication_contract_identity(imported.scope),
    policy,
    authority,
    imported.relations.map(@publication.publication_contract_identity),
    max_bytes,
    max_nodes,
    max_depth,
    scope=Some(imported.scope),
  )
}

///|
/// Both public Result and private Table exports retain the exact imported
/// Invocation and its live producer observations, without reissuing either.
fn client_effect_imported_evidence_matches_owner(
  imported : ClientEffectImportedEvidence,
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
) -> Bool {
  physical_equal(imported.owner, owner) &&
  physical_equal(imported.inputs, inputs) &&
  @strategy.captured_effect_inputs_match_computation(inputs, owner.graph) &&
  imported.observations.all(observed => {
    @strategy.captured_effect_result_import_matches(
      observed.captured,
      inputs,
      imported.invocation.unit,
      @strategy.captured_effect_result_import_producer(observed.captured),
    )
  })
}
