///|
/// Complete input provenance for one original Model Unit. Individual entries
/// remain ModelContribution and cannot become a whole-Unit Artifact. This
/// borrowed context neither owns the Model/Source nor authenticates custody.
struct ClientEffectModelAcquiredEvidence {
  compiled : ClientCompiledRun
  call_scope : ClientInferCallScope
  model : @publication.CapturedEffectDependencyBody
  invocation : ClientEffectLocalInvocation
  direct : Array[ClientEffectAcquiredEvidence]
  keyed : (ClientKeyedLookupInput, ClientKeyedNativeCompletion)?
  scope : @publication.PublicationContract
  retention : @publication.PublicationContract
  imports : ClientEffectImportedEvidence?
  scope_imports : Array[ClientScopeResultImportObservation]
  scope_relations : Array[@publication.PublicationContract]
}

///|
/// The original Model owner supplies its retained Scope and composed inputs.
/// No CID-only Source reconstruction, second request/Model, or contribution
/// upgrade is accepted. The caller backs these bounded metadata constructors.
pub fn issue_single_model_client_effect_acquired_evidence(
  compiled : ClientCompiledRun,
  call_scope : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
  sources : ClientInferComposedSources,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports? : ClientEffectImportedEvidence? = None,
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
) -> Result[
  ClientEffectModelAcquiredEvidence,
  ClientEffectAcquiredEvidenceIssue,
] {
  if !physical_equal(compiled.owner, call_scope.owner) ||
    !physical_equal(sources.occurrence.owner, call_scope.owner) ||
    !client_infer_occurrence_matches_plan(
      call_scope.plan.occurrence,
      call_scope.plan,
    ) ||
    !client_infer_composed_source_origin_matches(
      sources.occurrence,
      call_scope.plan.occurrence,
    ) {
    return Err(Invocation(ForeignCapturedInput))
  }
  if call_scope.named_sources.length() !=
    sources.inputs.length() + (if sources.keyed is Some(_) { 1 } else { 0 }) {
    return Err(Invocation(ForeignSourceObservation))
  }
  for input in sources.inputs {
    if !call_scope.named_sources.any(entry => {
        entry.0 == input.name && physical_equal(entry.1, input.observation)
      }) {
      return Err(Invocation(ForeignSourceObservation))
    }
  }
  let retained_keyed = match sources.keyed {
    None => {
      if call_scope.plan.keyed is Some(_) {
        return Err(Invocation(MissingCapturedInput))
      }
      None
    }
    Some((name, observation, admitted)) => {
      let lookup = observation.lookup
      if lookup.closed || lookup.left.lookup_issue is Some(_) {
        return Err(Invocation(ForeignCapturedInput))
      }
      guard lookup.identity is Some(_) &&
        lookup.native_completion is Some(completed) else {
        return Err(Invocation(MissingCapturedInput))
      }
      guard lookup.left.composed is Some(original) &&
        physical_equal(original.compiled, compiled) &&
        client_infer_occurrence_matches_plan(sources.occurrence, original.plan) else {
        return Err(Invocation(ForeignCapturedInput))
      }
      guard call_scope.named_sources.any(entry => {
          entry.0 == name && physical_equal(entry.1, admitted)
        }) &&
        physical_equal(observation.source, completed.source) &&
        physical_equal(observation.input, completed.input) else {
        return Err(Invocation(ForeignSourceObservation))
      }
      if client_infer_occurrence_coordinates(sources.occurrence) ==
        client_infer_occurrence_coordinates(call_scope.plan.occurrence) {
        guard physical_equal(original.plan, call_scope.plan) else {
          return Err(Invocation(ForeignCapturedInput))
        }
      } else {
        // The prior Model's complete lookup is transitive provenance of the
        // actual imported Result, not this Model's own lookup, root or scope.
        guard call_scope.plan.keyed is None &&
          imports.map(value => model_effect_imported_keyed(value, sources)) ==
          Some(true) else {
          return Err(Invocation(ForeignResultImport))
        }
      }
      Some((lookup, completed))
    }
  }
  let keyed = if client_infer_occurrence_coordinates(sources.occurrence) ==
    client_infer_occurrence_coordinates(call_scope.plan.occurrence) {
    retained_keyed
  } else {
    None
  }
  let scope_imports = if imports is None && !call_scope.result_inputs.is_empty() {
    match
      issue_scope_model_result_import_observations(
        match compiled.compilation {
          Effects(allowed) => allowed.compilation.owner
          _ => return Err(Invocation(ForeignCapturedInput))
        },
        call_scope,
        max_bytes,
        max_nodes,
        max_depth,
        before_body~,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Invocation(issue))
    }
  } else {
    []
  }
  let invocation = match
    issue_model_effect_local_invocation(
      compiled,
      call_scope,
      model,
      keyed.map(value => value.1),
      max_bytes,
      max_nodes,
      max_depth,
      imports=imports.map(value => (value, sources)),
      scope_imports~,
      scope_sources=Some(sources),
      before_body~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let direct = match
    build_model_effect_direct_sources(
      invocation,
      sources,
      retention,
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Static request encoding may invoke a Ref observer. Preserve the original
  // closure after that boundary; immutable equal-CID replacements do not win.
  if retained_keyed is Some((lookup, completed)) &&
    (
      lookup.closed ||
      lookup.left.lookup_issue is Some(_) ||
      !lookup.native_completion
      .map(value => physical_equal(value, completed))
      .unwrap_or(false)
    ) {
    return Err(Invocation(ForeignCapturedInput))
  }
  let scopes = []
  let scope_relations : Array[@publication.PublicationContract] = []
  for observed in scope_imports {
    let artifact = observed.input.artifact
    guard artifact.scope is Some(original_scope) else {
      return Err(Relation(@publication.WrongScope))
    }
    scopes.push(original_scope)
    let relation = match
      @publication.issue_derived_input_relation(
        artifact.artifact,
        artifact.evidence,
        original_scope,
        artifact.retention,
        max_bytes,
        max_nodes,
        max_depth,
        before_body~,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Relation(issue))
    }
    if !scope_relations.any(value => {
        @publication.publication_contract_identity(value) ==
        @publication.publication_contract_identity(relation)
      }) {
      scope_relations.push(relation)
    }
  }
  for index, source in direct {
    if model_effect_scope_imported_source(scope_imports, sources.inputs[index]) {
      continue
    }
    if !scope_imports.is_empty() {
      scope_relations.push(source.relation)
    }
    if imports
      .map(original => {
        model_effect_imported_source(original, sources.inputs[index])
      })
      .unwrap_or(false) {
      continue
    }
    scopes.push(source.scope)
  }
  if imports is Some(original) {
    scopes.push(original.scope)
  }
  if keyed is Some((lookup, _)) {
    guard lookup.publication_identity is Some(identity) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    scopes.push(identity.scope)
  }
  let scope = match
    @publication.issue_combined_acquisition_scope(
      scopes,
      max_bytes,
      max_nodes,
      max_depth,
      before_body~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
  }
  if !client_infer_result_input_inventory_current(call_scope) {
    return Err(Invocation(ForeignResultImport))
  }
  Ok({
    compiled,
    call_scope,
    model,
    invocation,
    direct,
    keyed,
    scope,
    retention,
    imports,
    scope_imports,
    scope_relations,
  })
}

///|
/// SAME original observation context, not a claim of Model execution/current
/// permission. client_infer_host retains those checks around this projection.
pub fn client_effect_model_acquired_matches(
  value : ClientEffectModelAcquiredEvidence,
  compiled : ClientCompiledRun,
  scope : ClientInferCallScope,
  model : @publication.CapturedEffectDependencyBody,
) -> Bool {
  physical_equal(value.compiled, compiled) &&
  physical_equal(value.call_scope, scope) &&
  physical_equal(value.model, model) &&
  client_infer_result_input_inventory_current(scope)
}

///|
pub fn client_effect_model_acquired_invocation(
  value : ClientEffectModelAcquiredEvidence,
) -> ClientEffectLocalInvocation {
  value.invocation
}

///|
/// Borrow the exact combined acquisition scope already retained by this Model
/// Unit. Its Artifact refers to this original scope, including keyed Content
/// and imported Sources. This neither reissues a scope nor grants access.
pub fn client_effect_model_acquired_scope_json(
  value : ClientEffectModelAcquiredEvidence,
) -> String {
  @publication.publication_contract_json(value.scope)
}

///|
/// Copy only the bounded pointer array; the original complete inventory stays
/// private even if a caller removes an entry from its returned view.
pub fn client_effect_model_acquired_direct_sources(
  value : ClientEffectModelAcquiredEvidence,
) -> Array[ClientEffectAcquiredEvidence] {
  value.direct.copy()
}

///|
/// Borrow the original compiler-issued Lookup barrier preimage. The same
/// live lookup retains its complete protocol evidence; this is semantic DATA,
/// not a fresh compiler, dependency admission, current permission or custody.
pub fn client_effect_model_acquired_lookup_barrier(
  value : ClientEffectModelAcquiredEvidence,
) -> (String, String)? {
  guard value.keyed is Some((lookup, completed)) &&
    !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_completion is Some(original) &&
    physical_equal(original, completed) &&
    value.call_scope.plan.keyed is Some(component) else {
    return None
  }
  Some(
    (
      component.barrier.logical_cid,
      @encode.document_text(component.barrier_body),
    ),
  )
}

///|
/// Borrow the complete original closure frozen before the Model Read. Its
/// original lookup retains all semantic bodies through the existing lifetime;
/// a copy of the pointer array cannot mutate that private retained inventory.
pub fn client_effect_model_acquired_lookup_dependency_bodies(
  value : ClientEffectModelAcquiredEvidence,
) -> Result[
  Array[@publication.CapturedEffectDependencyBody],
  ClientEffectLocalResultArtifactIssue,
] {
  guard value.keyed is Some((lookup, completed)) else { return Ok([]) }
  guard !lookup.closed &&
    lookup.left.lookup_issue is None &&
    lookup.native_completion is Some(same) &&
    physical_equal(same, completed) &&
    lookup.native_sources is Some(state) &&
    state.dependency_bodies is Some(bodies) else {
    return Err(ForeignOwner)
  }
  Ok(bodies.copy())
}

///|
/// Bind the named Result's exact export to the original completed Model host
/// output, directly or through its checked serial same-Unit suffix input.
/// The calling Model owner retains OutputUse/currentness; the captured
/// Run retains the same Result pin. No individual contribution can enter here
/// as a whole Unit, and equal rows or another completion are insufficient.
pub fn issue_model_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : ClientEffectModelAcquiredEvidence,
  expected_output : @execution.CompletedOutput,
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
  build_model_client_effect_local_result_artifact(
    owner,
    EffectInputs(inputs),
    exported,
    acquired,
    expected_output,
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
/// Semantic Artifact of the actual completed Model Unit, before later Models.
/// The original Unit pins, full CallScope and output/suffix receipt remain the
/// issuer's custody. Final Run publication is unbound until its real completion.
pub fn issue_preconsumer_model_client_effect_unit_result_artifact(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : ClientEffectModelAcquiredEvidence,
  expected_output : @execution.CompletedOutput,
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
  build_model_client_effect_local_result_artifact(
    owner,
    AcquiredUnit(inputs),
    exported,
    acquired,
    expected_output,
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
fn build_model_client_effect_local_result_artifact(
  owner : PreparedClientEffectComputation,
  custody : ClientEffectLocalArtifactCustody,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : ClientEffectModelAcquiredEvidence,
  expected_output : @execution.CompletedOutput,
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
  let model_task = acquired.call_scope.plan.task
  // Select using immutable identity, not a failed current observation or task
  // numbering. Preserve every old direct original; a declined direct branch
  // never retries through the suffix path.
  let original_matches = if @execution.completed_relation_export_has_output_identity(
      receipt, expected_output,
    ) {
    (match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        )
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_result_export_matches_receipt(
          inputs, exported, receipt,
        )
    }) &&
    @execution.completed_relation_export_matches_output(
      receipt, expected_output,
    )
  } else {
    match custody {
      EffectInputs(inputs) =>
        @strategy.captured_effect_local_result_export_matches_model_suffix(
          exported,
          inputs,
          owner.graph,
          invocation.unit,
          model_task,
          expected_output,
          receipt,
        )
      AcquiredUnit(inputs) =>
        @strategy.captured_effect_local_unit_result_export_matches_model_suffix(
          exported,
          inputs,
          owner.graph,
          invocation.unit,
          model_task,
          expected_output,
          receipt,
        )
    }
  }
  if !original_matches {
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
  let relations = match effect_model_acquired_relation_cids(acquired) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
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
fn effect_model_acquired_relation_cids(
  acquired : ClientEffectModelAcquiredEvidence,
) -> Result[Array[String], ClientEffectLocalResultArtifactIssue] {
  let relations = if !acquired.scope_relations.is_empty() {
    acquired.scope_relations.map(@publication.publication_contract_identity)
  } else {
    match acquired.imports {
      Some(original) =>
        original.relations.map(@publication.publication_contract_identity)
      None =>
        acquired.direct.map(value => {
          @publication.publication_contract_identity(value.relation)
        })
    }
  }
  if acquired.keyed is Some((lookup, completed)) {
    guard !lookup.closed &&
      lookup.left.lookup_issue is None &&
      lookup.native_completion is Some(same) &&
      physical_equal(same, completed) else {
      return Err(ForeignOwner)
    }
    relations.push(
      @publication.publication_contract_identity(completed.relation),
    )
  }
  relations.sort_by(@canonical_value.compare_utf16)
  Ok(relations)
}

///|
/// Public Result provenance from the same complete Model/local Artifact
/// owner. The private local Definition/Invocation never substitutes for the
/// public Named Result. This projects originals without another Model call,
/// compilation, Source read, policy join or physical custody claim.
pub fn client_effect_model_public_result_evidence_refs(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  acquired : ClientEffectModelAcquiredEvidence,
  artifact : ClientEffectLocalResultArtifact,
  result : Int,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
) -> Result[
  (String, Array[String], String, String, String),
  ClientEffectLocalResultArtifactIssue,
] {
  if !physical_equal(materials.compilation, materials.allowed.compilation) ||
    !physical_equal(materials.compilation.owner, materials.prepared) ||
    !physical_equal(acquired.invocation.owner, materials.prepared) ||
    !physical_equal(artifact.invocation, acquired.invocation) ||
    !(acquired.compiled.compilation is Effects(allowed) &&
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
  let relations = match effect_model_acquired_relation_cids(acquired) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
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
pub fn client_effect_model_acquired_scope_import_bodies(
  value : ClientEffectModelAcquiredEvidence,
) -> Array[(String, String, String)] {
  let bodies : Array[(String, String, String)] = []
  for observed in value.scope_imports {
    bodies.push(("result_import_observation", observed.cid, observed.wire))
  }
  for relation in value.scope_relations {
    bodies.push(
      (
        "acquisition_relation",
        @publication.publication_contract_identity(relation),
        @publication.publication_contract_json(relation),
      ),
    )
  }
  bodies
}

///|
/// Geometry from the same local Definition and Result evidence emitters, over
/// this actual completed Model's original Scope/import relations and receipt.
/// Future CID positions contribute only their fixed canonical width.
pub fn client_effect_model_unit_artifact_construction_geometry(
  owner : PreparedClientEffectComputation,
  acquired : ClientEffectModelAcquiredEvidence,
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
  let relations = match effect_model_acquired_relation_cids(acquired) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
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
