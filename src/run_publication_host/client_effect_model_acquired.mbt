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
) -> Result[
  ClientEffectModelAcquiredEvidence,
  ClientEffectAcquiredEvidenceIssue,
] {
  if !physical_equal(compiled.owner, call_scope.owner) ||
    !physical_equal(sources.occurrence.owner, call_scope.owner) ||
    !client_infer_occurrence_matches_plan(sources.occurrence, call_scope.plan) {
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
  let keyed = match sources.keyed {
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
        physical_equal(original.plan, call_scope.plan) else {
        return Err(Invocation(ForeignCapturedInput))
      }
      guard call_scope.named_sources.any(entry => {
          entry.0 == name && physical_equal(entry.1, admitted)
        }) &&
        physical_equal(observation.source, completed.source) &&
        physical_equal(observation.input, completed.input) else {
        return Err(Invocation(ForeignSourceObservation))
      }
      Some((lookup, completed))
    }
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
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let direct = match
    build_model_effect_direct_sources(
      invocation, sources, retention, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Static request encoding may invoke a Ref observer. Preserve the original
  // closure after that boundary; immutable equal-CID replacements do not win.
  if keyed is Some((lookup, completed)) &&
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
  for index, source in direct {
    if imports.map(original => model_effect_imported_source(original, sources.inputs[index])).unwrap_or(false) {
      continue
    }
    scopes.push(source.scope)
  }
  if imports is Some(original) { scopes.push(original.scope) }
  if keyed is Some((lookup, _)) {
    guard lookup.publication_identity is Some(identity) else {
      return Err(Invocation(ForeignSourceObservation))
    }
    scopes.push(identity.scope)
  }
  let scope = match
    @publication.issue_combined_acquisition_scope(
      scopes, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Relation(issue))
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
  physical_equal(value.model, model)
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
  let invocation = acquired.invocation
  let result = @strategy.captured_effect_local_result_export_result(exported)
  if !physical_equal(invocation.owner, owner) ||
    !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
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
    @strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) &&
    @execution.completed_relation_export_matches_output(
      receipt, expected_output,
    )
  } else {
    @strategy.captured_effect_local_result_export_matches_model_suffix(
      exported,
      inputs,
      owner.graph,
      invocation.unit,
      model_task,
      expected_output,
      receipt,
    )
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
  let custody = EffectInputs(inputs)
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
    @publication.resolve_run_local_result_context(
      admission, run_definition, run_invocation, observation,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
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
  let relations = match acquired.imports {
    Some(original) =>
      original.relations.map(@publication.publication_contract_identity)
    None =>
      acquired.direct.map(value => {
        @publication.publication_contract_identity(value.relation)
      })
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
    @publication.publication_contract_identity(artifact.run_invocation) !=
    @publication.publication_contract_identity(invocation) {
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
