///|
/// Closed provenance of a completed Local Unit. Every Result on this
/// unit uses a separately checked producer policy and its live export receipt.
struct ClientWholeLocalUnitPublication {
  invocation : ClientWholeLocalUnitInvocation
  retention : @publication.PublicationContract
  contributions : Array[ClientLocalSourceUnitContribution]
  imported_relations : Array[@publication.PublicationContract]?
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
fn client_whole_local_unit_publication_current(
  owner : ClientWholeLocalUnitOriginal,
) -> Bool {
  client_whole_local_unit_original_live(owner) &&
  (match owner.model {
    Some(model) => (model.current)()
    None =>
      client_infer_composed_whole_sources_match_run(
        owner.sources,
        owner.run,
        after_completion=true,
      )
  })
}

///|
/// The modeled Artifact must be the export of this Call's sealed terminal.
/// This borrows the classification already computed for the original A
/// input. It does not select or authorize a receiving Model.
struct ClientWholeModelEgressOriginal {
  plan : ClientInferPlanGraph
  artifact : ClientWholeLocalResultArtifact
  manifest : ClientWholeLocalResultManifest
  classification : @environment.DataClassification
}

///|
pub fn client_whole_model_egress_original_classification(
  value : ClientWholeModelEgressOriginal,
) -> @environment.DataClassification {
  value.classification
}

///|
pub fn verify_client_whole_model_egress_original(
  admission : ClientInferEgressAdmission,
  call : ClientInferCallScope,
  output : @execution.CompletedOutput,
  artifact : ClientWholeLocalResultArtifact,
  manifest : ClientWholeLocalResultManifest,
) -> Result[ClientWholeModelEgressOriginal, ClientInferEgressIssue] {
  let owner = artifact.invocation.owner
  guard owner.model is Some(model) &&
    physical_equal(model.call, call) &&
    client_infer_egress_matches_scope(admission, call) &&
    client_whole_model_terminal_output_matches(call, output) &&
    client_whole_local_result_manifest_member(manifest, artifact) is Some(index) &&
    (model.current)() &&
    @execution.completed_relation_export_matches_output(
      artifact.export_receipt,
      output,
    ) &&
    client_whole_model_terminal_matches(call, artifact.export_receipt) else {
    return Err(ForeignOwner)
  }
  check_client_infer_egress_observation(admission).bind(_ => {
    if client_whole_model_terminal_output_matches(call, output) &&
      client_infer_result_input_inventory_current(call) &&
      @strategy.captured_completed_unit_result_export_original(
        artifact.custody,
        owner.results,
        index,
      )
      is Some((_, receipt)) &&
      physical_equal(receipt, artifact.export_receipt) {
      Ok({
        plan: call.plan,
        artifact,
        manifest,
        classification: admission.classification,
      })
    } else {
      Err(ForeignOwner)
    }
  })
}

///|
fn client_whole_model_import_relations(
  imports : Array[ClientScopeResultImportObservation],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fund_body : (String, @encode.EncodingConstructionGeometry) -> Bool,
) -> Result[
  Array[(@publication.PublicationContract, @publication.PublicationContract)],
  ClientEffectAcquiredEvidenceIssue,
] {
  let relations = Array(capacity=imports.length())
  for observed in imports {
    guard observed.input.original is Whole(artifact, manifest, _) &&
      client_whole_local_result_manifest_matches(manifest, artifact) &&
      artifact.scope is Some(scope) else {
      return Err(Invocation(ForeignResultImport))
    }
    match
      @publication.issue_derived_input_relation(
        artifact.artifact,
        artifact.evidence,
        scope,
        artifact.retention,
        max_bytes,
        max_nodes,
        max_depth,
        before_body=Some(fund_body),
      ) {
      Ok(value) => relations.push((scope, value))
      Err(issue) => return Err(Relation(issue))
    }
  }
  Ok(relations)
}

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
  let imports = owner.model.map(model => model.imports)
  let import_count = imports.map(values => values.length()).unwrap_or(0)
  let count = sources.length().to_int64() + import_count.to_int64()
  if !client_whole_local_unit_original_live(owner) ||
    count <= 0 ||
    count > max_nodes.to_int64() {
    return Err(Invocation(ForeignCapturedInput))
  }
  if !fund_controls(count.to_int()) ||
    !client_whole_local_unit_publication_current(owner) {
    return Err(Invocation(ForeignCapturedInput))
  }
  let count = count.to_int()
  let observations = Array(capacity=sources.length())
  let inputs = Array(capacity=sources.length())
  let rows = Array(capacity=sources.length())
  let direct = if owner.model is Some(_) {
    Some(Array(capacity=sources.length()))
  } else {
    None
  }
  let backed = (name, geometry) => {
    fund_body(name, geometry) &&
    (owner.model is None || client_whole_local_unit_publication_current(owner))
  }
  for index, input in sources {
    guard input.original is Whole(acquisition) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    if direct is Some(slots) {
      let declaration = @acquisition.declaration(
        @acquisition.mode_input(
          @acquisition.source_acquisition_mode(acquisition),
        ),
      )
      if declaration.stage_index != owner.unit {
        continue
      }
      slots.push(index)
    }
    let request = @acquisition.source_acquisition_request(acquisition)
    let geometry = match
      @acquisition.parameterized_request_canonical_geometry(
        request, max_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(Invocation(Encoding))
    }
    if !backed("request_values", geometry) {
      return Err(Invocation(Encoding))
    }
    let (source, logical, _, _) = @publication.model_source_observation_originals(
      input.observation,
    )
    observations.push(source)
    inputs.push(logical)
    rows.push(@query.captured_source_relation_row_count(input.identity))
  }
  if !observations.is_empty() {
    let metadata = match
      @publication.source_unit_metadata_construction_geometry(
        observations,
        inputs,
        rows,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
        include_union=owner.model is None && count > 1,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
    for (name, geometry) in metadata {
      if !backed(name, geometry) {
        return Err(Invocation(Encoding))
      }
    }
  }
  if !client_whole_local_unit_publication_current(owner) {
    return Err(Invocation(ForeignCapturedInput))
  }
  let contributions = Array(capacity=observations.length())
  let scopes = Array(capacity=count)
  let relations = Array(capacity=count)
  for index in 0..<observations.length() {
    let slot = direct.map(slots => slots[index]).unwrap_or(index)
    let input = sources[slot]
    guard input.original is Whole(acquisition) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    let part = match
      prepare_client_local_source_unit_contribution(
        slot,
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
  let imported_relations = match imports {
    None => None
    Some(originals) => {
      let derived = match
        client_whole_model_import_relations(
          originals, max_bytes, max_nodes, max_depth, backed,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let bodies = Array(capacity=derived.length())
      for (scope, relation) in derived {
        bodies.push(relation)
        scopes.push(scope)
        let cid = @publication.publication_contract_identity(relation)
        if !relations.contains(cid) {
          relations.push(cid)
        }
      }
      Some(bodies)
    }
  }
  relations.sort_by(@canonical_value.compare_utf16)
  let scope = if scopes.length() == 1 {
    scopes[0]
  } else {
    match
      @publication.issue_combined_acquisition_scope(
        scopes,
        max_bytes,
        max_nodes,
        max_depth,
        before_body=if owner.model is Some(_) { Some(backed) } else { None },
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
  }
  Ok({
    invocation,
    retention,
    contributions,
    imported_relations,
    scope,
    relations,
  })
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
) -> Result[(String, Bool), ClientEffectLocalResultArtifactIssue] {
  let original = value.invocation.owner
  let program = @strategy.graph_program(
    original.scope.origin.compiled.owner.graph,
  )
  let count = value.contributions.length().to_int64()
  let sources = original.sources.inputs.length().to_int64()
  let imports = original.model
    .map(model => model.imports.length())
    .unwrap_or(0)
    .to_int64()
  let checks = match original.model {
    None => count * count
    Some(_) => sources * sources + imports * imports
  }
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
  guard selected is Some(policy) else { return Err(ForeignDefinition) }
  if original.model is Some(model) {
    guard value.imported_relations is Some(relations) &&
      relations.length() == model.imports.length() else {
      return Err(ForeignDefinition)
    }
    return client_whole_local_model_result_policy(
      model.call,
      original.sources,
      model.imports,
      policy,
      program,
    )
  }
  guard @checked.publication_policy_source_count(policy) ==
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
  Ok((policy.cid, false))
}

///|
fn client_whole_local_model_result_policy(
  call : ClientInferCallScope,
  sources : ClientInferComposedSources,
  imports : Array[ClientScopeResultImportObservation],
  policy : @checked.PublicationSourcePolicy,
  program : @checked.CheckedProgram,
) -> Result[(String, Bool), ClientEffectLocalResultArtifactIssue] {
  let source_count = @checked.publication_policy_source_count(policy)
  let import_count = @checked.publication_policy_import_count(policy)
  guard source_count <= sources.inputs.length() &&
    import_count <= imports.length() &&
    @checked.unit_pipeline(program, call.plan.occurrence.stage)
    is Some(pipeline) else {
    return Err(ForeignDefinition)
  }
  let selected_model = match
    @checked.publication_policy_model_step_count(policy) {
    0 => false
    1 => {
      let step = call.source_ordinal
      guard @checked.publication_policy_model_step_at(policy, 0)
        is Some(checked) &&
        checked.step == step &&
        @pipeline.step_at(pipeline, step) is Some(operation) &&
        operation.operation is @pipeline.Infer(infer) &&
        physical_equal(checked.infer, infer) else {
        return Err(ForeignDefinition)
      }
      true
    }
    _ => return Err(ForeignDefinition)
  }
  for index in 0..<source_count {
    let checked = @checked.publication_policy_source_at(policy, index).unwrap()
    let mut matches = 0
    for input in sources.inputs {
      if model_effect_source_original_matches_check(input.original, checked) {
        matches += 1
      }
    }
    if matches != 1 {
      return Err(ForeignDefinition)
    }
  }
  for index in 0..<import_count {
    let checked = @checked.publication_policy_import_at(policy, index).unwrap()
    let selected = @context.publication_row_limit_result(
      @checked.publication_selection(checked.publication),
    )
    guard @pipeline.input_at(pipeline, checked.input) is Some((name, _)) else {
      return Err(ForeignDefinition)
    }
    let mut matches = 0
    for imported in imports {
      if imported.input.interface.input_name == name &&
        imported.input.original is Whole(artifact, _, _) &&
        artifact.invocation.unit == selected.stage &&
        artifact.source.result_name ==
        @checked.publication_result_name(checked.publication) {
        matches += 1
      }
    }
    if matches != 1 {
      return Err(ForeignDefinition)
    }
  }
  Ok((policy.cid, selected_model))
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
  let (policy, modeled_result) = match
    client_whole_local_result_policy_cid(
      value, port, max_work, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let export_current = () => {
    client_whole_local_unit_publication_current(owner) &&
    (
      !modeled_result ||
      (
        owner.model is Some(model) &&
        client_whole_model_terminal_matches(model.call, receipt)
      )
    ) &&
    @strategy.captured_completed_unit_result_export_original(
      handoff,
      owner.results,
      index,
    )
    is Some((_, current)) &&
    physical_equal(current, receipt)
  }
  if owner.model is Some(_) && !export_current() {
    return Err(ForeignExport)
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
      if !fund_body("result_retention_policy", geometry) ||
        (owner.model is Some(_) && !export_current()) {
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
    !export_current() {
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
