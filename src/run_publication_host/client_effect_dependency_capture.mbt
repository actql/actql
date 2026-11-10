///|
pub(all) enum ClientEffectDependencyCaptureIssue {
  ForeignInput
  ForeignExport
  Dependency(@publication.CapturedEffectDependencyIssue)
  Static(@checked.LocalDependencyBodyIssue)
  ConstructionRefused
}

///|
/// Immutable dependency bodies from one actual checked Result export. This
/// does not establish Store custody or a complete Captured Run inventory.
struct ClientEffectDependencyCapture {
  artifact : ClientEffectLocalResultArtifact
  bodies : Array[@publication.CapturedEffectDependencyBody]
}

///|
/// Preserve the opaque Artifact owner when combining dependency captures.
/// Matching body identities alone cannot attest another preparation's input.
pub fn client_effect_dependency_capture_matches_artifact(
  value : ClientEffectDependencyCapture,
  artifact : ClientEffectLocalResultArtifact,
) -> Bool {
  physical_equal(value.artifact, artifact)
}

///|
pub fn client_effect_dependency_capture_bodies(
  value : ClientEffectDependencyCapture,
) -> Array[@publication.CapturedEffectDependencyBody] {
  value.bodies.copy()
}

///|
/// Check the exact live Result borrow before the Native adapter reads it.
/// Neither an equal Artifact CID nor a different Result in the same Unit
/// substitutes for that borrow.
pub fn client_effect_dependency_capture_matches(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  artifact : ClientEffectLocalResultArtifact,
  local_result : Int,
) -> Bool {
  if !client_effect_local_artifact_matches_inputs(artifact, inputs) ||
    !client_effect_local_artifact_matches_computation(
      artifact,
      materials.prepared,
    ) ||
    client_effect_local_artifact_run_definition_cid(artifact) !=
    Some(@publication.publication_contract_identity(materials.run_definition)) {
    return false
  }
  guard @strategy.captured_effect_local_result_at(inputs, local_result)
    is Some(result) else {
    return false
  }
  match artifact.source {
    ResultSource(borrow, _) =>
      @strategy.captured_any_result_borrows_share_view(
        borrow,
        @strategy.captured_effect_local_result_borrow(result),
      )
    TableSource(_, _) => false
  }
}

///|
/// Reuse typed dependency admission and the checked static bodies. The row
/// preimage and schema must hash to the exact export receipt and original
/// Artifact; caller-authored data cannot replace the completed Result.
pub fn admit_client_effect_dependency_capture(
  materials : ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  artifact : ClientEffectLocalResultArtifact,
  local_result : Int,
  exported : @strategy.CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
  rows_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body? : ((Int, Int, Int) -> Bool)? = None,
) -> Result[ClientEffectDependencyCapture, ClientEffectDependencyCaptureIssue] {
  if !client_effect_dependency_capture_matches(
      materials, inputs, artifact, local_result,
    ) {
    return Err(ForeignInput)
  }
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, receipt,
    ) ||
    !physical_equal(
      @strategy.captured_effect_local_result_export_result(exported),
      @strategy.captured_effect_local_result_at(inputs, local_result).unwrap(),
    ) ||
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(receipt),
    ) !=
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(artifact.export_receipt),
    ) ||
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(receipt),
    ) !=
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(
        artifact.export_receipt,
      ),
    ) {
    return Err(ForeignExport)
  }
  if max_bytes < 1 || max_bytes > 16777216 {
    return Err(Dependency(InvalidLimits))
  }
  let bodies : Array[@publication.CapturedEffectDependencyBody] = []
  let mut remaining = max_bytes
  fn append(
    kind : String,
    cid : String?,
    wire : String,
  ) -> Result[Unit, ClientEffectDependencyCaptureIssue] {
    let (body, bytes) = match
      admit_client_effect_dependency_capture_body(
        kind,
        cid,
        wire,
        remaining,
        max_nodes,
        max_depth,
        before_body,
        () => {
          client_effect_dependency_capture_matches(
            materials, inputs, artifact, local_result,
          )
        },
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remaining -= bytes
    bodies.push(body)
    Ok(())
  }
  let schema = @execution.completed_relation_export_schema_identity(receipt)
  let relation = @execution.completed_relation_export_identity(receipt)
  let definition = match artifact.source {
    ResultSource(_, value) => value
    TableSource(_, _) => return Err(ForeignInput)
  }
  let entries = [
    (
      "relation_value",
      Some(@execution.logical_relation_cid(relation)),
      "{\"sort\":\"relation\",\"value\":" + rows_wire + "}",
    ),
    (
      "relation_schema",
      Some(@execution.relation_schema_cid(schema)),
      @execution.relation_schema_wire(schema),
    ),
    ("local_result_definition", None, definition.wire),
    ("local_computation", None, artifact.invocation.wire),
    (
      "result_artifact",
      None,
      client_effect_local_result_artifact_json(artifact),
    ),
    (
      "derivation_evidence",
      None,
      client_effect_local_result_derivation_json(artifact),
    ),
    (
      "ordering_evidence",
      None,
      client_effect_local_result_ordering_json(artifact),
    ),
    (
      "result_retention_policy",
      None,
      @publication.publication_contract_json(artifact.retention),
    ),
  ]
  for (kind, cid, wire) in entries {
    match append(kind, cid, wire) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(materials.prepared),
  )
  let static_bodies = match
    @checked.checked_local_dependency_bodies(
      program,
      artifact.invocation.unit,
      4096 - bodies.length(),
      remaining,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Static(issue))
  }
  for (kind, body) in static_bodies {
    match
      append(
        kind,
        Some(@checked.checked_local_dependency_body_cid(body)),
        @checked.checked_local_dependency_body_json(body),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok({ artifact, bodies, })
}

///|
// Keep the allocation/current boundary shared by every dependency kind. The
// original Result check is repeated only across an actual Host callback.
fn admit_client_effect_dependency_capture_body(
  kind : String,
  cid : String?,
  wire : String,
  remaining : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body : ((Int, Int, Int) -> Bool)?,
  original : () -> Bool,
) -> Result[
  (@publication.CapturedEffectDependencyBody, Int),
  ClientEffectDependencyCaptureIssue,
] {
  let bytes = match before_body {
    // Preserve the existing uninstrumented entrance, including its UTF8
    // encoder's handling of invalid caller text. The funded Native entrance
    // below only consumes original generated immutable contract wires.
    None => @utf8.encode(wire).length()
    Some(_) =>
      match @scalar.admit_utf8_length(wire, remaining) {
        Ok(value) => value
        Err(@scalar.LimitExceeded) => return Err(Dependency(ByteLimit))
        Err(_) => return Err(Dependency(InvalidBody))
      }
  }
  if bytes > remaining {
    return Err(Dependency(ByteLimit))
  }
  if before_body is Some(prepare) {
    // Every JSON node consumes at least one original input byte. These are
    // backing dimensions only; the semantic parser keeps its original limits.
    if !prepare(
        bytes,
        Int::min(max_nodes, Int::max(1, bytes)),
        Int::min(max_depth, Int::min(max_nodes, Int::max(1, bytes))),
      ) {
      return Err(ConstructionRefused)
    }
    if !original() {
      return Err(ForeignInput)
    }
  }
  match
    @publication.admit_captured_effect_dependency_body(
      kind, cid, wire, remaining, max_nodes, max_depth,
    ) {
    Ok(body) => Ok((body, bytes))
    Err(issue) => Err(Dependency(issue))
  }
}
