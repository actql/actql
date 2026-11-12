///|
// Original Source observations admitted once by the existing Run invocation
// owner. Retaining them issues no completed Unit or right to read again.
priv struct ClientDirectSourceInputs {
  occurrences : ClientDirectAcquisitionOccurrences
  captures : Array[@query.CapturedInputSource]
  identities : Array[@query.CapturedSourceRelationIdentity]
  originals : Array[ClientDirectSourceOriginal]
  sources : Array[@publication.RunEvidenceValue]
  inputs : Array[@publication.RunEvidenceValue]
  data_policy_cid : String
}

///|
priv struct ClientDirectSourceObservation {
  original : ClientDirectSourceInputs
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
}

///|
/// Original Source inputs for completed Units, before later Model observations
/// exist. This is not a Run Invocation or a completed publication.
struct ClientEffectSourceUnitInputs {
  owner : PreparedClientEffectComputation
  source : ClientDirectSourceInputs
  run_definition_cid : String
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
  original : ClientEffectSourceUnitInputs
  final_context : (
    @publication.PublicationContract,
    @publication.RunEvidenceValue,
  )?
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
  prepare_client_effect_source_unit_body(
    {
      owner: value.owner,
      source: value.source.original,
      run_definition_cid: value.run_definition_cid,
    },
    Some((value.source.invocation, value.source.observation)),
    unit,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Prepare the same Unit semantics without synthesizing a whole-Run observation.
pub fn prepare_client_effect_source_unit(
  value : ClientEffectSourceUnitInputs,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectCombinedSourceUnit, ClientEffectAcquiredEvidenceIssue] {
  prepare_client_effect_source_unit_body(
    value,
    None,
    unit,
    retention,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn prepare_client_effect_source_unit_body(
  value : ClientEffectSourceUnitInputs,
  final_context : (
    @publication.PublicationContract,
    @publication.RunEvidenceValue,
  )?,
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
  let (definition, values, contracts) = match
    client_effect_source_unit_definition(value, unit) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
        client_effect_whole_source_request_material(
          acquisition, max_bytes, max_nodes, max_depth,
        )
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
    original: value,
    final_context,
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
  let source = value.original.source
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
  before_body? : ((Int, Int, Int) -> Bool)? = None,
) -> Result[Array[(String, String, String)], ClientEffectAcquiredEvidenceIssue] {
  let program = @checked.effect_program_static_checked_computation(
    value.original.owner.candidate,
  )
  let bodies = []
  let seen : Map[String, Bool] = Map([])
  let mut remaining = Int::min(max_bytes, 16777216)
  for part in value.contributions {
    let references = match
      @publication.source_effect_catalog_dependencies(
        value.original.source.sources[part.slot],
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
          before_body~,
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
  build_combined_source_client_effect_result_artifact(
    owner,
    EffectInputs(inputs),
    exported,
    combined,
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
/// Same checked Artifact issuer with the existing pre-consumer Unit custody.
/// No Unit/Result is reissued and no final Effect input owner is synthesized.
pub fn issue_combined_source_client_effect_unit_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
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
  build_combined_source_client_effect_result_artifact(
    owner,
    AcquiredUnit(inputs),
    exported,
    combined,
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
fn build_combined_source_client_effect_result_artifact(
  owner : PreparedClientEffectComputation,
  custody : ClientEffectLocalArtifactCustody,
  exported : @strategy.CapturedEffectLocalResultExport,
  combined : ClientEffectCombinedSourceUnit,
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
  let source = combined.original.source
  if !physical_equal(combined.original.owner, owner) ||
    !(match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_inputs_match_computation(inputs, owner.graph)
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_inputs_match_computation(
          inputs,
          owner.graph,
        )
    }) ||
    !@strategy.captured_effect_local_result_export_matches_computed_unit(
      exported,
      owner.graph,
      combined.invocation.unit,
    ) ||
    !combined.contributions.all(part => {
      @query.captured_source_available(source.captures[part.slot]) &&
      (match custody {
        EffectInputs(inputs) =>
          @strategy.captured_effect_inputs_acquired_source_matches(
            inputs,
            combined.invocation.unit,
            source.identities[part.slot],
          )
        AcquiredUnit(inputs) =>
          @strategy.captured_effect_local_unit_acquired_source_matches(
            inputs,
            source.identities[part.slot],
          )
      })
    }) {
    return Err(ForeignOwner)
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
  if combined.original.run_definition_cid !=
    @publication.publication_contract_identity(run_definition) ||
    (match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_inputs_run_definition_cid(inputs)
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_inputs_run_definition_cid(inputs)
    }) !=
    Some(combined.original.run_definition_cid) ||
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
      if combined.final_context
        is Some((original_invocation, original_observation)) &&
        (
          !physical_equal(invocation, original_invocation) ||
          !physical_equal(observation, original_observation)
        ) {
        return Err(ForeignInvocation)
      }
      // A pre-consumer Source Unit has no final observation yet. Its original
      // checked Run/custody above and the complete context below must still
      // match; no Model observation is synthesized from Source contributions.
      let (_, policy, authority) = match
        @publication.resolve_run_local_result_evidence_refs(
          admission,
          run_definition,
          invocation,
          observation,
          combined.retention,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Context(issue))
      }
      (Some(invocation), policy, authority)
    }
    None => {
      // Only the actual pre-consumer Unit custody may precede the final Run
      // observation. Its semantic Artifact will not acquire publication rights.
      guard custody is AcquiredUnit(_) && combined.final_context is None else {
        return Err(ForeignInvocation)
      }
      let policy = source.data_policy_cid
      let same_retention = match
        @publication.issue_result_retention_for_data_policy(
          combined.retention,
          policy,
          max_bytes,
          max_nodes,
          max_depth,
        ) {
        Ok(value) => value
        Err(_) => return Err(Context(@publication.ForeignRetention))
      }
      if @publication.publication_contract_identity(same_retention) !=
        @publication.publication_contract_identity(combined.retention) {
        return Err(Context(@publication.ForeignRetention))
      }
      (None, policy, @publication.run_publication_execution_context(admission))
    }
  }
  if !(match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_local_result_export_retained(inputs, exported)
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_result_export_retained(
          inputs, exported,
        )
    }) {
    return Err(ForeignExport)
  }
  build_client_effect_local_result_artifact(
    custody,
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

///|
/// Complete semantic Artifact of the original producer Unit before its later
/// Model consumer. Final Run publication is deliberately unbound here.
pub fn issue_preconsumer_client_effect_unit_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  combined : ClientEffectCombinedSourceUnit,
  definition : ClientEffectLocalResultDefinition,
  receipt : @execution.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectLocalResultArtifact,
  ClientEffectLocalResultArtifactIssue,
] {
  build_combined_source_client_effect_result_artifact(
    owner,
    AcquiredUnit(inputs),
    exported,
    combined,
    definition,
    receipt,
    admission,
    run_definition,
    None,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn client_effect_source_unit_definition(
  value : ClientEffectSourceUnitInputs,
  unit : Int,
) -> Result[(String, String, String), ClientEffectAcquiredEvidenceIssue] {
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
  Ok((definition, values, contracts))
}

///|
/// Original Unit body sizes from its actual Request and semantic emitters.
/// The original parent must admit the returned variable backings BEFORE the
/// corresponding Source Unit constructor. Fixed controls remain Common-owned.
/// `request_values` and `local_computation` are wire-only borrowed definitions;
/// other names select their existing PublicationContract constructor layout.
pub fn client_effect_source_unit_construction_geometry(
  value : ClientEffectSourceUnitInputs,
  unit : Int,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  Array[(String, @encode.EncodingConstructionGeometry)],
  ClientEffectAcquiredEvidenceIssue,
] {
  let (definition, values, contracts) = match
    client_effect_source_unit_definition(value, unit) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let source = value.source
  let bodies : Array[(String, @encode.EncodingConstructionGeometry)] = []
  let sources = []
  let inputs = []
  let rows = []
  let observations = []
  for slot, coordinate in source.occurrences.coordinates {
    if coordinate.0 != unit {
      continue
    }
    match source.originals[slot] {
      QuerySourceOriginal(_) => () // SAME admitted Query document is borrowed.
      WholeSourceOriginal(acquisition) => {
        let geometry = match
          @acquisition.parameterized_request_canonical_geometry(
            @acquisition.source_acquisition_request(acquisition),
            max_bytes,
            max_nodes,
            max_depth,
          ) {
          Ok(value) => value
          Err(_) => return Err(Invocation(Encoding))
        }
        bodies.push(("request_values", geometry))
      }
    }
    sources.push(source.sources[slot])
    inputs.push(source.inputs[slot])
    rows.push(
      @query.captured_source_relation_row_count(source.identities[slot]),
    )
    observations.push(
      @publication.run_evidence_value_identity(source.sources[slot]),
    )
  }
  if sources.length() < 2 {
    return Err(Invocation(MissingCapturedInput))
  }
  let metadata = match
    @publication.source_unit_metadata_construction_geometry(
      sources, inputs, rows, retention, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  for body in metadata {
    bodies.push(body)
  }
  let writer = @encode.construction_measuring_writer(
    max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Invocation(Encoding))
  }
  let geometry = try {
    emit_client_effect_local_invocation(
      writer,
      definition,
      values,
      contracts,
      @checked.checked_local_policy_cid(
        @checked.effect_program_static_checked_computation(
          value.owner.candidate,
        ),
      ),
      observations,
      Some(definition),
    )
    @encode.finish_construction_measurement(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(Invocation(Encoding))
    }
  }
  bodies.push(("local_computation", geometry))
  Ok(bodies)
}

///|
/// Pure same-parent/Run binding for the constructor's existing installing owner.
pub fn client_effect_source_unit_inputs_match(
  value : ClientEffectSourceUnitInputs,
  owner : PreparedClientEffectComputation,
  definition : @publication.PublicationContract,
) -> Bool {
  physical_equal(value.owner, owner) &&
  value.run_definition_cid ==
  @publication.publication_contract_identity(definition)
}

///|
/// Alias correspondence only; no current callback or new evidence issuance.
pub fn client_effect_combined_source_unit_matches_inputs(
  value : ClientEffectCombinedSourceUnit,
  inputs : ClientEffectSourceUnitInputs,
) -> Bool {
  physical_equal(value.original, inputs)
}
