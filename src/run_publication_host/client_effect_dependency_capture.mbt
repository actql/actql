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
pub fn client_effect_dependency_capture_body_count(
  value : ClientEffectDependencyCapture,
) -> Int {
  value.bodies.length()
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
  let original = () => {
    client_effect_dependency_capture_matches(
      materials, inputs, artifact, local_result,
    )
  }
  fn append(
    kind : String,
    cid : String?,
    wire : String,
    measured : (Int, Int)?,
    measured_depth : Int?,
    wrap_relation_rows : Bool,
  ) -> Result[Unit, ClientEffectDependencyCaptureIssue] {
    let measured = if before_body is Some(_) { measured } else { None }
    let (body, bytes) = match
      admit_client_effect_dependency_capture_body(
        kind,
        cid,
        wire,
        remaining,
        max_nodes,
        max_depth,
        before_body,
        original,
        wire_extent=measured,
        wire_depth=measured_depth,
        enforce_extent=true,
        wrap_relation_rows~,
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
  // Both values already have an exact canonical writer measurement on this
  // matched receipt. Limit the parser too: equal byte lengths alone do not
  // bound a caller-provided wire to the original node count.
  let (relation_bytes, relation_nodes, _) = @execution.logical_relation_usage(
    relation,
  )
  let (schema_bytes, schema_nodes, _) = @execution.relation_schema_usage(schema)
  match
    append(
      "relation_value",
      Some(@execution.logical_relation_cid(relation)),
      rows_wire,
      Some((relation_bytes, relation_nodes)),
      None,
      true,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    append(
      "relation_schema",
      Some(@execution.relation_schema_cid(schema)),
      @execution.relation_schema_wire(schema),
      Some((schema_bytes, schema_nodes)),
      None,
      false,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  for
    (kind, wire) in [
      ("local_result_definition", definition.wire),
      ("local_computation", artifact.invocation.wire),
    ] {
    match append(kind, None, wire, None, None, false) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  // The artifact already owns these canonical contracts. The funded path
  // adopts the same values after checking currentness, instead of building
  // another tree under a byte-count estimate for each contract's nodes.
  for
    (kind, contract) in [
      ("result_artifact", artifact.artifact),
      (
        "derivation_evidence",
        @publication.result_ordering_derivation_contract(artifact.evidence),
      ),
      (
        "ordering_evidence",
        @publication.result_ordering_evidence_contract(artifact.evidence),
      ),
      ("result_retention_policy", artifact.retention),
    ] {
    match
      capture_client_effect_publication_dependency(
        kind, contract, remaining, max_nodes, max_depth, before_body, original,
      ) {
      Ok((body, bytes)) => {
        remaining -= bytes
        bodies.push(body)
      }
      Err(issue) => return Err(issue)
    }
  }
  let program = @checked.effect_program_static_checked_computation(
    prepared_client_effect_computation_candidate(materials.prepared),
  )
  let static_bodies = match
    @checked.checked_local_dependency_bodies_with_wire_usage(
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
  for (kind, body, bytes, nodes, depth) in static_bodies {
    match
      append(
        kind,
        Some(@checked.checked_local_dependency_body_cid(body)),
        @checked.checked_local_dependency_body_json(body),
        Some((bytes, nodes)),
        Some(depth),
        false,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok({ artifact, bodies, })
}

///|
// Charge the original final encoder dimensions before constructing the typed
// edges. Currentness is observed after the funding callback, as for raw
// admission. When the original carries no usage, keep the raw admission path.
fn capture_client_effect_publication_dependency(
  kind : String,
  contract : @publication.PublicationContract,
  remaining : Int,
  max_nodes : Int,
  max_depth : Int,
  before_body : ((Int, Int, Int) -> Bool)?,
  original : () -> Bool,
) -> Result[
  (@publication.CapturedEffectDependencyBody, Int),
  ClientEffectDependencyCaptureIssue,
] {
  guard before_body is Some(prepare) &&
    @publication.publication_contract_wire_usage(contract)
    is Some((bytes, nodes, depth)) else {
    return admit_client_effect_dependency_capture_body(
      kind,
      None,
      @publication.publication_contract_json(contract),
      remaining,
      max_nodes,
      max_depth,
      before_body,
      original,
    )
  }
  if bytes > remaining {
    return Err(Dependency(ByteLimit))
  }
  if nodes > max_nodes || depth > max_depth {
    return Err(Dependency(InvalidBody))
  }
  if !prepare(bytes, nodes, depth) {
    return Err(ConstructionRefused)
  }
  if !original() {
    return Err(ForeignInput)
  }
  @publication.capture_publication_effect_dependency_body(
    kind, contract, remaining, max_nodes, max_depth,
  )
  .map(body => (body, bytes))
  .map_err(issue => ClientEffectDependencyCaptureIssue::Dependency(issue))
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
  wire_extent? : (Int, Int)? = None,
  wire_depth? : Int? = None,
  enforce_extent? : Bool = false,
  wrap_relation_rows? : Bool = false,
) -> Result[
  (@publication.CapturedEffectDependencyBody, Int),
  ClientEffectDependencyCaptureIssue,
] {
  let relation_prefix = "{\"sort\":\"relation\",\"value\":"
  let deferred_relation = wrap_relation_rows && before_body is Some(_)
  let wire = if wrap_relation_rows && !deferred_relation {
    relation_prefix + wire + "}"
  } else {
    wire
  }
  // The snapshot wire already belongs to the caller. Include the ASCII
  // wrapper in the same body quote before allocating its new text.
  let wrapper_bytes = if deferred_relation {
    relation_prefix.length() + 1
  } else {
    0
  }
  if remaining < wrapper_bytes {
    return Err(Dependency(ByteLimit))
  }
  let payload_bytes = match before_body {
    // Preserve the existing uninstrumented entrance, including its UTF8
    // encoder's handling of invalid caller text. The funded Native entrance
    // below only consumes original generated immutable contract wires.
    None => @utf8.encode(wire).length()
    Some(_) =>
      match @scalar.admit_utf8_length(wire, remaining - wrapper_bytes) {
        Ok(value) => value
        Err(@scalar.LimitExceeded) => return Err(Dependency(ByteLimit))
        Err(_) => return Err(Dependency(InvalidBody))
      }
  }
  let bytes = payload_bytes + wrapper_bytes
  if bytes > remaining {
    return Err(Dependency(ByteLimit))
  }
  // Only original encoder facts supply this bound. Raw/external wires retain
  // the full conservative parser quote.
  // Exact byte equality is checked here; complete canonical body/CID
  // admission remains below and cannot be replaced by these DATA dimensions.
  let (nodes, depth) = match wire_extent {
    Some((original_bytes, nodes)) => {
      let depth = wire_depth.unwrap_or(Int::min(max_depth, nodes))
      if original_bytes != bytes ||
        nodes < 1 ||
        nodes > max_nodes ||
        depth < 0 ||
        depth > max_depth {
        return Err(Dependency(InvalidBody))
      }
      (nodes, Int::max(1, depth))
    }
    None =>
      (
        Int::min(max_nodes, Int::max(1, bytes)),
        Int::min(max_depth, Int::min(max_nodes, Int::max(1, bytes))),
      )
  }
  if before_body is Some(prepare) {
    // Every JSON node consumes at least one original input byte. These are
    // backing dimensions only; the semantic parser keeps its original limits.
    if !prepare(bytes, nodes, depth) {
      return Err(ConstructionRefused)
    }
    if !original() {
      return Err(ForeignInput)
    }
  }
  let wire = if deferred_relation { relation_prefix + wire + "}" } else { wire }
  let (parse_bytes, parse_nodes, parse_depth) = if enforce_extent &&
    wire_extent is Some(_) {
    (bytes, nodes, depth)
  } else {
    (remaining, max_nodes, max_depth)
  }
  match
    @publication.admit_captured_effect_dependency_body(
      kind, cid, wire, parse_bytes, parse_nodes, parse_depth,
    ) {
    Ok(body) => Ok((body, bytes))
    Err(issue) => Err(Dependency(issue))
  }
}
