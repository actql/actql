///|
// Original Source observations admitted once by the existing Run invocation
// owner. Retaining them issues no completed Unit or right to read again.
priv struct ClientDirectSourceObservation {
  occurrences : ClientDirectAcquisitionOccurrences
  captures : Array[@query.CapturedInputSource]
  identities : Array[@query.CapturedSourceRelationIdentity]
  originals : Array[ClientDirectSourceOriginal]
  sources : Array[@publication.RunEvidenceValue]
  inputs : Array[@publication.RunEvidenceValue]
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
}

///|
struct ClientEffectDirectSourcesPublication {
  owner : PreparedClientEffectComputation
  source : ClientDirectSourceObservation
  run_definition_cid : String
}

///|
priv struct ClientEffectSourceUnitContribution {
  slot : Int
  request : @encode.EncodedDocument
  request_cid : String
  retention : @publication.PublicationContract
  relation : @publication.PublicationContract
  ordering : @publication.PublicationContract
  scope : @publication.PublicationContract
}

///|
/// Semantic preparation for all original Sources in one checked Unit. A
/// completed producer is required separately at the Result Artifact issuer.
struct ClientEffectCombinedSourceUnit {
  publication : ClientEffectDirectSourcesPublication
  invocation : ClientEffectLocalInvocation
  contributions : Array[ClientEffectSourceUnitContribution]
  relations : Array[@publication.PublicationContract]
  scope : @publication.PublicationContract
  retention : @publication.PublicationContract
}

///|
pub fn client_effect_direct_sources_publication_invocation(
  value : ClientEffectDirectSourcesPublication,
) -> @publication.PublicationContract {
  value.source.invocation
}

///|
pub fn client_effect_direct_sources_publication_observation(
  value : ClientEffectDirectSourcesPublication,
) -> @publication.RunEvidenceValue {
  value.source.observation
}

///|
/// The exact checked inventory chooses every occurrence in this Unit. No
/// individual Source contribution enters the old single-producer issuer.
pub fn prepare_client_effect_combined_source_unit(
  value : ClientEffectDirectSourcesPublication,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectCombinedSourceUnit, ClientEffectAcquiredEvidenceIssue] {
  let owner = value.owner
  let source = value.source
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard client_direct_acquisition_occurrences_match_effect_program(
      source.occurrences,
      owner,
    ) &&
    @checked.unit_definition_cid(program, unit) is Some(definition) &&
    @checked.unit_used_values_cid(program, unit) is Some(values) &&
    @checked.unit_contracts_cid(program, unit) is Some(contracts) &&
    @checked.unit_pipeline(program, unit) is Some(pipeline) &&
    client_effect_source_unit_without_model(pipeline) &&
    @checked.unit_result_import_count(program, unit) == Some(0) &&
    @checked.unit_import_cid_count(program, unit) == Some(0) else {
    return Err(Invocation(MissingUnit))
  }
  let contributions : Array[ClientEffectSourceUnitContribution] = []
  let scopes : Array[@publication.PublicationContract] = []
  let relations : Array[@publication.PublicationContract] = []
  let observations : Array[String] = []
  for slot, coordinate in source.occurrences.coordinates {
    if coordinate.0 != unit {
      continue
    }
    let original = source.originals[slot]
    let material = match original {
      QuerySourceOriginal(requirement) => {
        let material = @planning.query_requirement_material(requirement)
        Ok(
          (
            @planning.query_material_request(material),
            @planning.query_material_cids(material).0,
          ),
        )
      }
      WholeSourceOriginal(acquisition) =>
        @acquisition.parameterized_request_document(
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
    let (request, request_cid) = match material {
      Ok(value) => value
      Err(issue) => return Err(Invocation(issue))
    }
    let facts = match original {
      QuerySourceOriginal(requirement) =>
        @planning.query_requirement_source_evidence_facts(requirement)
      WholeSourceOriginal(acquisition) =>
        @planning.source_acquisition_evidence_facts(acquisition)
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
    let (relation, ordering, scope) = match
      @publication.issue_captured_source_input_relation(
        source.inputs[slot],
        source.sources[slot],
        request_cid,
        @query.captured_source_relation_row_count(source.identities[slot]),
        source_retention,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
    contributions.push({
      slot,
      request,
      request_cid,
      retention: source_retention,
      relation,
      ordering,
      scope,
    })
    scopes.push(scope)
    observations.push(
      @publication.run_evidence_value_identity(source.sources[slot]),
    )
    if !relations.any(original => {
        @publication.publication_contract_identity(original) ==
        @publication.publication_contract_identity(relation)
      }) {
      relations.push(relation)
    }
  }
  if contributions.length() < 2 {
    return Err(Invocation(MissingCapturedInput))
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
  let invocation = match
    issue_client_effect_local_invocation_body(
      owner,
      unit,
      definition,
      values,
      contracts,
      @checked.checked_local_policy_cid(program),
      observations,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  if !contributions.all(part => {
      @query.captured_source_available(source.captures[part.slot])
    }) {
    return Err(Invocation(ForeignCapturedInput))
  }
  Ok({
    publication: value,
    invocation,
    contributions,
    relations,
    scope,
    retention,
  })
}

///|
pub fn client_effect_combined_source_unit_invocation(
  value : ClientEffectCombinedSourceUnit,
) -> ClientEffectLocalInvocation {
  value.invocation
}

///|
/// Original metadata preimages for this Unit's full provenance. Source
/// occurrences stay distinct; consumers deduplicate only dependency CIDs.
pub fn client_effect_combined_source_unit_dependency_bodies(
  value : ClientEffectCombinedSourceUnit,
) -> Array[(String, String, String)] {
  let source = value.publication.source
  let bodies = [
    (
      "acquisition_scope",
      @publication.publication_contract_identity(value.scope),
      @publication.publication_contract_json(value.scope),
    ),
    (
      "result_retention_policy",
      @publication.publication_contract_identity(value.retention),
      @publication.publication_contract_json(value.retention),
    ),
  ]
  for part in value.contributions {
    let input = source.inputs[part.slot]
    let observation = source.sources[part.slot]
    bodies.push(
      (
        "source_input_logical",
        @publication.run_evidence_value_identity(input),
        @publication.run_evidence_value_json(input),
      ),
    )
    bodies.push(
      (
        "source_evidence",
        @publication.run_evidence_value_identity(observation),
        @publication.run_evidence_value_json(observation),
      ),
    )
    bodies.push(
      ("request_values", part.request_cid, @encode.document_text(part.request)),
    )
    for
      (kind, contract) in [
        ("acquisition_relation", part.relation),
        ("ordering_evidence", part.ordering),
        ("acquisition_scope", part.scope),
        ("result_retention_policy", part.retention),
      ] {
      bodies.push(
        (
          kind,
          @publication.publication_contract_identity(contract),
          @publication.publication_contract_json(contract),
        ),
      )
    }
  }
  bodies
}

///|
pub fn client_effect_combined_source_unit_catalog_bodies(
  value : ClientEffectCombinedSourceUnit,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[(String, String, String)], ClientEffectAcquiredEvidenceIssue] {
  let program = @checked.effect_program_static_checked_computation(
    value.publication.owner.candidate,
  )
  let bodies = []
  let seen : Map[String, Bool] = Map([])
  let mut remaining = Int::min(max_bytes, 16777216)
  for part in value.contributions {
    let references = match
      @publication.source_effect_catalog_dependencies(
        value.publication.source.sources[part.slot],
      ) {
      Ok(value) => value
      Err(_) => return Err(Dependency(MissingDependency))
    }
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
        Ok(value) => value
        Err(issue) => return Err(Dependency(issue))
      }
      let wire = @checked.checked_local_dependency_body_json(body)
      remaining -= @utf8.encode(wire).length()
      bodies.push(
        (role, @checked.checked_local_dependency_body_cid(body), wire),
      )
      seen[key] = true
    }
  }
  Ok(bodies)
}

///|
/// Publish only the actual computed Result of this Unit, with the SAME live
/// Run inputs, every original Source and the exact completed export receipt.
pub fn issue_combined_source_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  combined : ClientEffectCombinedSourceUnit,
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
  let source = combined.publication.source
  if !physical_equal(combined.publication.owner, owner) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !@strategy.captured_effect_local_result_export_matches_computed_unit(
      exported,
      owner.graph,
      combined.invocation.unit,
    ) ||
    !combined.contributions.all(part => {
      @query.captured_source_available(source.captures[part.slot]) &&
      @strategy.captured_effect_inputs_acquired_source_matches(
        inputs,
        combined.invocation.unit,
        source.identities[part.slot],
      )
    }) {
    return Err(ForeignOwner)
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) {
    return Err(ForeignExport)
  }
  let result = @strategy.captured_effect_local_result_export_result(exported)
  let borrow = @strategy.captured_effect_local_result_borrow(result)
  if !client_effect_local_result_definition_matches(
      definition,
      owner,
      combined.invocation.unit,
      @execution.managed_result_occurrence_name(
        @strategy.captured_any_result_borrow_occurrence(borrow),
      ),
    ) {
    return Err(ForeignDefinition)
  }
  if combined.publication.run_definition_cid !=
    @publication.publication_contract_identity(run_definition) ||
    @strategy.captured_effect_inputs_run_definition_cid(inputs) !=
    Some(combined.publication.run_definition_cid) ||
    !physical_equal(run_invocation, source.invocation) ||
    !physical_equal(observation, source.observation) ||
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
      combined.retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  build_client_effect_local_result_artifact(
    EffectInputs(inputs),
    ResultSource(borrow, definition),
    combined.invocation,
    receipt,
    run_invocation,
    combined.retention,
    @publication.publication_contract_identity(combined.scope),
    policy,
    authority,
    combined.relations.map(@publication.publication_contract_identity),
    max_bytes,
    max_nodes,
    max_depth,
    scope=Some(combined.scope),
  )
}
