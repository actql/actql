///|
pub(all) enum ClientEffectCaptureInventoryIssue {
  ForeignInput
  Source(ClientEffectAcquiredEvidenceIssue)
  LocalSource(@publication.CapturedLocalEffectSourceIssue)
  Dependency(@publication.CapturedEffectDependencyIssue)
}

///|
/// A confirmed transferred Artifact carries the receiver's checked context,
/// while the original acquired fact retains the sender's independent context.
/// Join their immutable evidence only after checking the complete original
/// semantic identity and the exact live receiver import. This grants no read,
/// write or execution authority and reissues no acquisition evidence.
fn transferred_effect_capture_acquired_context(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  observed : ClientEffectResultImportObservation,
  acquired : ClientEffectAcquiredEvidence,
) -> ClientEffectAcquiredEvidence? {
  let receiver = observed.artifact
  if !client_effect_local_artifact_matches_inputs(receiver, inputs) ||
    !client_effect_local_artifact_matches_computation(
      receiver,
      materials.prepared,
    ) ||
    !client_effect_local_invocation_matches(
      receiver.invocation,
      materials.prepared,
      0,
    ) ||
    !client_effect_local_invocation_matches(
      acquired.invocation,
      acquired.owner,
      0,
    ) ||
    prepared_client_effect_identity(acquired.owner) !=
    prepared_client_effect_identity(materials.prepared) ||
    prepared_client_effect_computation_definition_cid(acquired.owner) !=
    prepared_client_effect_computation_definition_cid(materials.prepared) ||
    prepared_client_effect_computation_semantics_cid(acquired.owner) !=
    prepared_client_effect_computation_semantics_cid(materials.prepared) ||
    prepared_client_effect_computation_environment_cid(acquired.owner) !=
    prepared_client_effect_computation_environment_cid(materials.prepared) ||
    receiver.invocation.cid != acquired.invocation.cid ||
    receiver.invocation.wire != acquired.invocation.wire ||
    receiver.invocation.unit_definition_cid !=
    acquired.invocation.unit_definition_cid {
    return None
  }
  guard receiver.scope is Some(scope) else { return None }
  if @publication.publication_contract_identity(scope) !=
    @publication.publication_contract_identity(acquired.scope) ||
    @publication.publication_contract_json(scope) !=
    @publication.publication_contract_json(acquired.scope) ||
    @publication.publication_contract_identity(receiver.retention) !=
    @publication.publication_contract_identity(acquired.publication_retention) {
    return None
  }
  Some({
    ..acquired,
    owner: materials.prepared,
    invocation: receiver.invocation,
  })
}

///|
/// Connect one acquired producer and its imported consumer to the existing
/// Captured Run dependency Owner. Roots come from the exact admitted Effect
/// source, not a caller-provided CID list. This does not transfer physical
/// custody, authorize a write or commit a waiting Run.
pub fn issue_client_effect_capture_inventory(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  source : @publication.CapturedEffectSourceArtifact,
  manifest : ClientEffectLocalManifest,
  artifact : ClientEffectLocalResultArtifact,
  imported : ClientEffectImportedEvidence,
  acquired : ClientEffectAcquiredEvidence,
  acquired_relation_wire : String,
  acquired_schema_wire : String,
  captures : Array[ClientEffectDependencyCapture],
  retention_bodies : Array[@publication.CapturedEffectDependencyBody],
  limits : @publication.CapturedEffectDependencyLimits,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (
    @publication.CapturedLocalEffectSourceEvidence,
    @publication.CapturedEffectDependencyInventory,
  ),
  ClientEffectCaptureInventoryIssue,
] {
  if limits.max_entries < 0 ||
    limits.max_entries > 4096 ||
    limits.max_total_bytes < 1 ||
    limits.max_total_bytes > 16777216 ||
    captures.length() > limits.max_entries ||
    retention_bodies.length() > limits.max_entries {
    return Err(Dependency(InvalidLimits))
  }
  if !physical_equal(imported.owner, materials.prepared) ||
    !physical_equal(imported.inputs, inputs) ||
    imported.observations.length() != 1 ||
    !physical_equal(artifact.invocation, imported.invocation) ||
    !client_effect_local_source_matches(
      materials.prepared,
      inputs,
      member_index,
      manifest,
      imported.invocation,
      artifact,
      source,
    ) {
    return Err(ForeignInput)
  }
  let observed = imported.observations[0]
  let acquired = if physical_equal(acquired.owner, materials.prepared) {
    acquired
  } else {
    match
      transferred_effect_capture_acquired_context(
        materials, inputs, observed, acquired,
      ) {
      Some(value) => value
      None => return Err(ForeignInput)
    }
  }
  if !@strategy.captured_effect_result_import_matches(
      observed.captured,
      inputs,
      imported.invocation.unit,
      @strategy.captured_effect_result_import_producer(observed.captured),
    ) ||
    !physical_equal(observed.artifact.invocation, acquired.invocation) ||
    client_effect_local_artifact_run_invocation_cid(observed.artifact) is None ||
    client_effect_local_artifact_run_invocation_cid(observed.artifact) !=
    client_effect_local_artifact_run_invocation_cid(artifact) {
    return Err(ForeignInput)
  }
  let required = [observed.artifact, artifact]
  if captures.length() != required.length() {
    return Err(ForeignInput)
  }
  for original in required {
    if captures
      .filter(capture => physical_equal(capture.artifact, original))
      .length() !=
      1 {
      return Err(ForeignInput)
    }
  }
  let local_source = match
    admit_client_effect_local_source_evidence(
      materials.prepared,
      inputs,
      member_index,
      manifest,
      imported.invocation,
      artifact,
      source,
      limits.max_total_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(LocalSource(issue))
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  let seen : Map[String, String] = Map([])
  let mut remaining = limits.max_total_bytes
  fn retain(
    body : @publication.CapturedEffectDependencyBody,
  ) -> Result[Unit, ClientEffectCaptureInventoryIssue] {
    let key = @publication.captured_effect_dependency_body_kind(body) +
      "\u0000" +
      @publication.captured_effect_dependency_body_cid(body)
    let wire = @publication.captured_effect_dependency_body_json(body)
    if seen.get(key) is Some(previous) {
      if previous != wire {
        return Err(Dependency(DuplicateIdentity))
      }
      // Shared checked static/schema/retention bodies have one identity. This
      // does not merge distinct physical holdings or their cleanup charges.
      return Ok(())
    }
    if bodies.length() >= limits.max_entries {
      return Err(Dependency(EntryLimit))
    }
    let bytes = @utf8.encode(wire).length()
    if bytes > remaining {
      return Err(Dependency(ByteLimit))
    }
    remaining -= bytes
    bodies.push(body)
    seen[key] = wire
    Ok(())
  }
  fn append(
    kind : String,
    cid : String?,
    wire : String,
  ) -> Result[Unit, ClientEffectCaptureInventoryIssue] {
    let body = match
      @publication.admit_captured_effect_dependency_body(
        kind,
        cid,
        wire,
        limits.max_total_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Dependency(issue))
    }
    retain(body)
  }
  for capture in captures {
    for body in capture.bodies {
      match retain(body) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  for body in retention_bodies {
    if !["retention_contract", "metadata_retention_policy", "clock_contract"].contains(
        @publication.captured_effect_dependency_body_kind(body),
      ) {
      return Err(Dependency(WrongDependencyKind))
    }
    match retain(body) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for
    (kind, cid, wire) in [
      (
        "relation_value",
        Some(@query.captured_source_relation_logical_cid(acquired.identity)),
        acquired_relation_wire,
      ),
      (
        "relation_schema",
        Some(@query.captured_source_relation_schema_cid(acquired.identity)),
        acquired_schema_wire,
      ),
      ("result_import_observation", None, observed.wire),
      ("local_manifest", None, observed.manifest.wire),
      (
        "acquisition_scope",
        None,
        @publication.publication_contract_json(imported.scope),
      ),
    ] {
    match append(kind, cid, wire) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for relation in imported.relations {
    match
      append(
        "acquisition_relation",
        None,
        @publication.publication_contract_json(relation),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  for (kind, wire) in client_effect_acquired_dependency_bodies(acquired) {
    match
      append(
        kind,
        if kind == "request_values" {
          Some(acquired.request_cid)
        } else {
          None
        },
        wire,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let catalog = match
    client_effect_acquired_catalog_bodies(
      acquired,
      limits.max_total_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  for (kind, cid, wire) in catalog {
    match append(kind, Some(cid), wire) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let root = match
    @publication.admit_publication_effect_dependency_body(
      "result_artifact",
      client_effect_local_result_artifact_json(artifact),
      limits.max_total_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dependency(issue))
  }
  let inventory = match
    @publication.issue_captured_effect_dependency_inventory(
      bodies,
      [root],
      limits,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dependency(issue))
  }
  // Re-admit against the exact captured local source root used by Captured
  // Run issuance/recovery. No missing or unused body is silently repaired.
  match
    @publication.admit_captured_effect_source_dependencies(
      [local_source],
      @publication.captured_effect_dependency_inventory_json(inventory),
      limits.max_total_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => Ok((local_source, value))
    Err(issue) => Err(Dependency(issue))
  }
}
