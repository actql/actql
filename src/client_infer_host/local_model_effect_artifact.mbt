///|
/// Complete provenance from the SAME live Model output and accepted issuer.
/// The enclosing capture operation backs and retains the returned metadata;
/// neither this projection nor an individual Source contribution grants apply.
pub fn issue_original_local_model_acquired_evidence(
  value : LocalModelObservation,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports? : @publication_host.ClientEffectImportedEvidence? = None,
  source_originals? : Array[@publication_host.ClientEffectAcquiredEvidence] = [],
) -> Result[
  @publication_host.ClientEffectModelAcquiredEvidence,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.call_scope is Some(scope) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let result = match
    (
      value.held.owner.saved_call_scope,
      value.held.owner.composed_sources,
      imports,
    ) {
    (Some(saved), None, Some(original)) =>
      @publication_host.issue_restored_model_client_effect_imported_evidence(
        value.issued.state.compiled,
        scope,
        saved,
        value.body,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
        original,
        source_originals,
      )
    (None, Some(sources), _) =>
      @publication_host.issue_single_model_client_effect_acquired_evidence(
        value.issued.state.compiled,
        scope,
        value.body,
        sources,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
        imports~,
      )
    _ => Err(Invocation(ForeignCapturedInput))
  }
  if !original_local_model_observation_current(value.held, value.issued) {
    return Err(Invocation(ForeignCapturedInput))
  }
  result
}

///|
/// Bind the exported Result to this exact original completed Model output.
/// Run observation/Invocation come from the retained issuer, not caller wire.
/// Saved restoration remains a separate authenticated original entrance.
pub fn issue_original_local_model_effect_artifact(
  value : LocalModelObservation,
  materials : @publication_host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : @publication_host.ClientEffectModelAcquiredEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @relation.CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  guard value.issued.state.observation is Some(observation) &&
    value.issued.state.invocation is Some(invocation) else {
    return Err(ForeignOwner)
  }
  issue_original_local_model_effect_artifact_with_context(
    value,
    materials.prepared,
    inputs,
    exported,
    acquired,
    definition,
    receipt,
    @publication_host.client_effect_allowed_run_admission(materials.allowed),
    materials.run_definition,
    invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// The installed publisher already retains these original typed contracts.
/// Require the SAME complete issuer context; do not reconstruct materials or
/// accept a Source-only invocation in place of the original Model invocation.
/// Existing artifact admission still binds the actual output/Result/current
/// custody and full publication tuple. This grants no Store/Effect authority.
pub fn issue_original_local_model_effect_artifact_with_context(
  value : LocalModelObservation,
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  acquired : @publication_host.ClientEffectModelAcquiredEvidence,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @relation.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  guard original_local_model_observation_current(value.held, value.issued) &&
    value.held.owner.call_scope is Some(scope) &&
    @publication_host.client_effect_model_acquired_matches(
      acquired,
      value.issued.state.compiled,
      scope,
      value.body,
    ) &&
    @publication.publication_contract_identity(run_definition) ==
    @publication.publication_contract_identity(value.issued.state.definition) &&
    value.issued.state.observation is Some(original_observation) &&
    physical_equal(observation, original_observation) &&
    value.issued.state.invocation is Some(original_invocation) &&
    physical_equal(invocation, original_invocation) else {
    return Err(ForeignOwner)
  }
  let result = @publication_host.issue_model_client_effect_local_result_artifact(
    owner,
    inputs,
    exported,
    acquired,
    value.held.output,
    definition,
    receipt,
    admission,
    run_definition,
    invocation,
    observation,
    max_bytes,
    max_nodes,
    max_depth,
  )
  if !original_local_model_observation_current(value.held, value.issued) {
    return Err(ForeignOwner)
  }
  result
}

///|
/// A completed Model Unit may precede later Models in the SAME compiled Run.
/// Borrow its genuine CallScope and unfiltered outcome receipt; this is a local
/// semantic contribution, never a completed whole-Run ObservationSet or grant.
/// The existing parent backs and retains this constructor before entry.
pub fn issue_preconsumer_original_model_acquired_evidence(
  held : OutputUse,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  receipt : @relation.CompletedRelationExportReceipt,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  imports? : @publication_host.ClientEffectImportedEvidence? = None,
  source_originals? : Array[@publication_host.ClientEffectAcquiredEvidence] = [],
  before_body? : ((String, @encode.EncodingConstructionGeometry) -> Bool)? = None,
  parent_ledger? : @resources.Ledger? = None,
) -> Result[
  PreconsumerModelUnitEvidence,
  @publication_host.ClientEffectAcquiredEvidenceIssue,
] {
  if parent_ledger is Some(parent) &&
    !held.owner.model
    .map(model => @model.original_completed_model_matches_parent(model, parent))
    .unwrap_or(false) {
    return Err(Invocation(ForeignCapturedInput))
  }
  guard prepare_preconsumer_model_unit_observation(
      held, compiled, definition, plan, receipt, max_bytes, max_nodes, max_depth,
    )
    is Some(body) &&
    held.owner.call_scope is Some(scope) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  let result = match
    (held.owner.saved_call_scope, held.owner.composed_sources, imports) {
    (Some(saved), None, Some(original)) =>
      @publication_host.issue_restored_model_client_effect_imported_evidence(
        compiled, scope, saved, body, retention, max_bytes, max_nodes, max_depth,
        original, source_originals,
      )
    (None, Some(sources), _) =>
      @publication_host.issue_single_model_client_effect_acquired_evidence(
        compiled,
        scope,
        body,
        sources,
        retention,
        max_bytes,
        max_nodes,
        max_depth,
        imports~,
        before_body~,
      )
    _ => Err(Invocation(ForeignCapturedInput))
  }
  guard original_host_output_matches(held, compiled, definition, plan) &&
    borrow_original_model_observation_relations(
      held, compiled, definition, plan,
    )
    is Some((_, outcomes)) else {
    return Err(Invocation(ForeignCapturedInput))
  }
  result.map(acquired => {
    held,
    compiled,
    definition,
    plan,
    body,
    receipt,
    outcomes,
    acquired,
  })
}

///|
/// A borrowed association of an existing OutputUse and its one semantic body.
/// It owns no Resource, publication permission or independent cleanup duty.
struct PreconsumerModelUnitEvidence {
  held : OutputUse
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  plan : @publication_host.ClientInferPlanGraph
  body : @publication.CapturedEffectDependencyBody
  receipt : @relation.CompletedRelationExportReceipt
  outcomes : @relation.CompletedOutput
  acquired : @publication_host.ClientEffectModelAcquiredEvidence
}

///|
pub fn preconsumer_model_unit_acquired_evidence(
  value : PreconsumerModelUnitEvidence,
) -> @publication_host.ClientEffectModelAcquiredEvidence? {
  guard original_host_output_matches(
      value.held,
      value.compiled,
      value.definition,
      value.plan,
    ) &&
    value.held.owner.call_scope is Some(scope) &&
    @publication_host.client_effect_model_acquired_matches(
      value.acquired,
      value.compiled,
      scope,
      value.body,
    ) &&
    @relation.completed_relation_export_matches_output(
      value.receipt,
      value.outcomes,
    ) else {
    return None
  }
  if !original_host_output_matches(
      value.held,
      value.compiled,
      value.definition,
      value.plan,
    ) {
    return None
  }
  Some(value.acquired)
}

///|
/// Use the one original Model semantic body for its actual completed Unit
/// Result/suffix. Neither a global Model ObservationSet nor final Run binding
/// is synthesized before the remaining Models execute.
pub fn issue_preconsumer_original_model_unit_artifact(
  value : PreconsumerModelUnitEvidence,
  owner : @publication_host.PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectLocalUnitInputs,
  exported : @strategy.CapturedEffectLocalResultExport,
  definition : @publication_host.ClientEffectLocalResultDefinition,
  receipt : @relation.CompletedRelationExportReceipt,
  admission : @publication.RunPublicationAdmission,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientEffectLocalResultArtifact,
  @publication_host.ClientEffectLocalResultArtifactIssue,
] {
  guard preconsumer_model_unit_acquired_evidence(value) is Some(acquired) else {
    return Err(ForeignOwner)
  }
  let result = @publication_host.issue_preconsumer_model_client_effect_unit_result_artifact(
    owner,
    inputs,
    exported,
    acquired,
    value.held.output,
    definition,
    receipt,
    admission,
    value.definition,
    max_bytes,
    max_nodes,
    max_depth,
  )
  if !original_host_output_matches(
      value.held,
      value.compiled,
      value.definition,
      value.plan,
    ) {
    return Err(ForeignOwner)
  }
  result
}

///|
/// Borrow the original semantic body and FIRST input scan without rebuilding
/// either. The outcome relation body is supplied by its caller's retained scan.
pub fn preconsumer_model_unit_dependency_bodies(
  value : PreconsumerModelUnitEvidence,
) -> Array[(String, String, String)]? {
  guard preconsumer_model_unit_acquired_evidence(value) is Some(_) &&
    original_model_input_bodies(value.held) is Some(inputs) &&
    value.held.owner.identity is Some(scan) &&
    @relation.completed_relation_identity_scan_body_receipt(scan)
    is Some(receipt) else {
    return None
  }
  let logical = @relation.logical_relation_cid(
    @relation.completed_relation_export_identity(receipt),
  )
  let schema = @relation.relation_schema_cid(
    @relation.completed_relation_export_schema_identity(receipt),
  )
  let bodies = [
    (
      "local_model_observation",
      @publication.captured_effect_dependency_body_cid(value.body),
      @publication.captured_effect_dependency_body_json(value.body),
    ),
  ]
  for (kind, wire) in inputs {
    bodies.push(
      (kind, if kind == "relation_value" { logical } else { schema }, wire),
    )
  }
  Some(bodies)
}

///|
/// Attach the already retained local observation to the real final issuer.
/// The binding must own the SAME original Model; no receipt/body/issuer is
/// reissued and no preconsumer token can stand in for the whole Run proof.
pub fn bind_preconsumer_model_unit_observation(
  binding : InvocationBinding,
  value : PreconsumerModelUnitEvidence,
) -> LocalModelObservation? {
  guard preconsumer_model_unit_acquired_evidence(value) is Some(_) &&
    binding.issuance is Some(issued) &&
    physical_equal(binding.output_use.owner, value.held.owner) &&
    physical_equal(issued.state.compiled, value.compiled) &&
    physical_equal(issued.state.definition, value.definition) &&
    original_local_model_observation_current(value.held, issued) else {
    return None
  }
  Some({ held: value.held, issued, body: value.body, })
}
