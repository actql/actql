///|
// Size-only traversal over admitted immutable values. No canonical value,
// key vector or text is constructed until the Host funds the returned extent.
fn capture_value_construction_extent(
  value : @json.CanonicalValue,
  work : (Int) -> Bool,
) -> @encode.EncodingConstructionGeometry? {
  let writer = @encode.work_construction_census_writer(
    2147483647, 2147483647, 64, work,
  ) catch {
    _ => return None
  }
  try {
    @json.emit_value(value, writer)
    Some(@encode.finish_construction_measurement(writer))
  } catch {
    _ => None
  }
}

///|
// Plan strings are existing admitted preview children. This preflight observes
// their actual source representation without constructing a parse tree. The
// ordinary issuer still performs its exact plan/Preview identity validation.
fn capture_plan_construction_extent(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> (Int, Int, Int)? {
  if wire.length() == 2147483647 || !work(wire.length() + 1) {
    return None
  }
  let cursor = match
    @source.start_json_source_preflight(
      wire,
      { max_input_bytes: max_bytes, max_nodes, max_depth, },
      data_keys=true,
    ) {
    Ok(cursor) => cursor
    Err(_) => return None
  }
  defer @source.cancel_json_source_preflight(cursor)
  while true {
    match @source.advance_json_source_preflight(cursor, 4096) {
      Ok(@source.JsonSourceReady(geometry, ..)) =>
        return Some(
          (geometry.input_bytes, geometry.node_upper, geometry.depth_upper),
        )
      Ok(@source.JsonSourceContinue(..)) => ()
      _ => return None
    }
  } nobreak {
    None
  }
}

///|
// Conservative encoded-key spelling from O(1) borrowed UTF16 length. This is
// numeric DATA, not a Resource grant, and does not traverse the String.
fn capture_map_key_extent(name : String) -> Int64 {
  4L + 6L * name.length().to_int64()
}

///|
fn captured_effectful_run_construction_extent(
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity,
  plan_names : Array[String],
  plan_wires : Array[String],
  dependencies : CapturedEffectDependencyInventory,
  dependency_geometry : @encode.EncodingConstructionGeometry,
  content_generations : Array[BoundContentGeneration],
  max_body_bytes : Int,
  max_body_nodes : Int,
  max_body_depth : Int,
  work : (Int) -> Bool,
) -> CapturedRunConstructionExtent? {
  if plan_names.length() != plan_wires.length() ||
    dependencies.wire.length() > dependency_geometry.bytes ||
    dependency_geometry.bytes < 2 ||
    dependency_geometry.nodes < 1 ||
    dependency_geometry.depth < 1 ||
    max_body_depth < 1 ||
    max_body_depth > 64 {
    return None
  }
  guard capture_value_construction_extent(receipt.value, work)
    is Some(receipt_extent) &&
    capture_value_construction_extent(authoring.value, work)
    is Some(authoring_extent) else {
    return None
  }
  let mut bytes = capture_context_extent_skeleton.length().to_int64() +
    capture_outer_extent_skeleton.length().to_int64() +
    capture_context_identity_extent.length().to_int64() +
    capture_outer_identity_extent.length().to_int64() +
    receipt_extent.bytes.to_int64() +
    authoring_extent.bytes.to_int64() +
    dependency_geometry.bytes.to_int64()
  let mut nodes = 25L +
    receipt_extent.nodes.to_int64() +
    authoring_extent.nodes.to_int64() +
    dependency_geometry.nodes.to_int64()
  let mut metadata_nodes = nodes
  let mut depth = Int::max(
    3,
    Int::max(
      receipt_extent.depth + 1,
      Int::max(authoring_extent.depth + 2, dependency_geometry.depth + 2),
    ),
  )
  let mut source_work = 0L
  let mut fields = 0L
  let mut max_fields = 0
  for snapshot in snapshots {
    if !work(1) ||
      snapshot.row_wire_bytes < 2 ||
      snapshot.row_nodes < 1 ||
      snapshot.row_depth < 1 {
      return None
    }
    guard capture_value_construction_extent(snapshot.artifact.value, work)
      is Some(artifact) else {
      return None
    }
    bytes += 3L * capture_map_key_extent(snapshot.name) +
      artifact.bytes.to_int64() +
      snapshot.row_wire_bytes.to_int64() +
      2L
    nodes += artifact.nodes.to_int64() +
      snapshot.row_nodes.to_int64() +
      1L +
      snapshot.fields.length().to_int64()
    metadata_nodes += artifact.nodes.to_int64() +
      1L +
      snapshot.fields.length().to_int64()
    fields += snapshot.fields.length().to_int64()
    max_fields = Int::max(max_fields, snapshot.fields.length())
    depth = Int::max(depth, Int::max(artifact.depth, snapshot.row_depth) + 3)
    for field in snapshot.fields {
      if !work(1) {
        return None
      }
      bytes += 3L + 6L * field.length().to_int64()
    }
  }
  for source in sources {
    if !work(1) {
      return None
    }
    guard capture_value_construction_extent(source.artifact.value, work)
      is Some(artifact) else {
      return None
    }
    source_work += 8L * artifact.bytes.to_int64() +
      16L * artifact.nodes.to_int64() +
      128L * source.effect_id.length().to_int64()
    bytes += 2L * capture_map_key_extent(source.effect_id) +
      artifact.bytes.to_int64() +
      3L +
      6L * source.holding_cid.length().to_int64()
    nodes += artifact.nodes.to_int64() + 1L
    metadata_nodes += artifact.nodes.to_int64() + 1L
    depth = Int::max(depth, artifact.depth + 3)
  }
  for source in local_sources {
    if !work(1) {
      return None
    }
    guard capture_value_construction_extent(source.value, work) is Some(value) else {
      return None
    }
    source_work += 8L * value.bytes.to_int64() +
      16L * value.nodes.to_int64() +
      128L * source.effect_id.length().to_int64()
    bytes += capture_map_key_extent(source.effect_id) + value.bytes.to_int64()
    nodes += value.nodes.to_int64()
    metadata_nodes += value.nodes.to_int64()
    depth = Int::max(depth, value.depth + 3)
  }
  for advance in advances {
    if !work(1) {
      return None
    }
    guard capture_value_construction_extent(advance.value, work) is Some(value) else {
      return None
    }
    bytes += 1L + value.bytes.to_int64()
    nodes += value.nodes.to_int64()
    metadata_nodes += value.nodes.to_int64()
    depth = Int::max(depth, value.depth + 3)
  }
  for model in models {
    if !work(1) {
      return None
    }
    guard capture_value_construction_extent(model.value, work) is Some(value) else {
      return None
    }
    bytes += value.bytes.to_int64() +
      4L +
      6L * model.identity.length().to_int64()
    nodes += value.nodes.to_int64() + 1L
    metadata_nodes += value.nodes.to_int64() + 1L
    depth = Int::max(depth, value.depth + 3)
  }
  for index in 0..<preview.member_effect_ids.length() {
    if !work(1) {
      return None
    }
    let name = preview.member_effect_ids[index]
    // Effects retains an empty object per member; logical plans are optional.
    bytes += capture_map_key_extent(name) + 2L
    nodes += 1L
    metadata_nodes += 1L
    if preview.member_effect_plan_cids[index] is Some(cid) {
      bytes += capture_map_key_extent(name) + 3L + 6L * cid.length().to_int64()
      nodes += 1L
      metadata_nodes += 1L
    }
  }
  for index in 0..<plan_names.length() {
    if !work(1) {
      return None
    }
    guard capture_plan_construction_extent(
        plan_wires[index],
        max_body_bytes,
        max_body_nodes,
        max_body_depth,
        work,
      )
      is Some((b, n, d)) else {
      return None
    }
    bytes += capture_map_key_extent(plan_names[index]) + b.to_int64()
    nodes += n.to_int64()
    metadata_nodes += n.to_int64()
    depth = Int::max(depth, d + 3)
  }
  if !content_generations.is_empty() {
    // Generated field name/array and five fixed member keys per observation.
    bytes += 24L
    nodes += 1L
    metadata_nodes += 1L
    for generation in content_generations {
      if !work(1) {
        return None
      }
      bytes += 3L + 5L * 30L
      nodes += 1L
      metadata_nodes += 1L
      for field in 0..<5 {
        guard content_generation_capture_field_data(generation, field)
          is Some(value) &&
          capture_value_construction_extent(value, work) is Some(value_extent) else {
          return None
        }
        bytes += value_extent.bytes.to_int64()
        nodes += value_extent.nodes.to_int64()
        metadata_nodes += value_extent.nodes.to_int64()
        depth = Int::max(depth, value_extent.depth + 4)
      }
    }
  }
  if bytes < 1L ||
    bytes > 2147483647L ||
    nodes < 1L ||
    nodes > 2147483647L ||
    metadata_nodes > 2147483647L ||
    fields > 2147483647L {
    return None
  }
  Some({
    max_wire_bytes: bytes.to_int(),
    max_nodes: nodes.to_int(),
    max_depth: depth,
    metadata_nodes: metadata_nodes.to_int(),
    results: snapshots.length(),
    total_fields: fields.to_int(),
    max_fields,
    models: models.length(),
    source_work,
  })
}

///|
// The caller funds copied reference inventories before entry, then reserves
// the returned same-input constructor facts before consuming this plan.
pub fn prepare_original_effectful_capture_plan(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  sources : Array[CapturedEffectSourceArtifact],
  local_sources : Array[CapturedLocalEffectSourceEvidence],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  preview : EffectPreviewIdentity,
  plan_names : Array[String],
  plan_wires : Array[String],
  dependencies : CapturedEffectDependencyInventory,
  dependency_geometry : @encode.EncodingConstructionGeometry,
  content_generations : Array[BoundContentGeneration],
  max_body_bytes : Int,
  max_body_nodes : Int,
  max_body_depth : Int,
  work : (Int) -> Bool,
  original_limits? : (Int, Int, Int, Int)? = None,
) -> CapturedRunConstructionPlan? {
  guard captured_effectful_run_construction_extent(
      receipt, snapshots, sources, local_sources, advances, authoring, models, preview,
      plan_names, plan_wires, dependencies, dependency_geometry, content_generations,
      max_body_bytes, max_body_nodes, max_body_depth, work,
    )
    is Some(extent) else {
    return None
  }
  if !work(definitions.length()) ||
    !work(artifacts.length()) ||
    !work(snapshots.length()) ||
    !work(sources.length()) ||
    !work(local_sources.length()) ||
    !work(advances.length()) ||
    !work(models.length()) ||
    !work(content_generations.length()) ||
    !work(plan_names.length()) {
    return None
  }
  let plans : Array[(String, String)] = []
  for index in 0..<plan_names.length() {
    plans.push((plan_names[index], plan_wires[index]))
  }
  // A caller moving an existing issuer to a measured plan keeps its
  // independent codec and workspace limits. The extent remains the sizing
  // facts of these immutable inputs, even when those limits are smaller.
  let (bytes, nodes, depth, workspace) = original_limits.unwrap_or(
    (
      extent.max_wire_bytes,
      extent.max_nodes,
      extent.max_depth,
      publication_evidence_workspace(extent.max_nodes),
    ),
  )
  Some({
    inputs: Some({
      run_definition,
      invocation,
      definitions: definitions.copy(),
      artifacts: artifacts.copy(),
      manifest,
      receipt,
      snapshots: snapshots.copy(),
      sources: sources.copy(),
      local_sources: local_sources.copy(),
      advances: advances.copy(),
      authoring,
      models: models.copy(),
      content_generations: content_generations.copy(),
      preview: Some(preview),
      plan_values: plans,
      max_wire_bytes: bytes,
      max_nodes: nodes,
      max_depth: depth,
      dependency_inventory: Some(dependencies),
    }),
    extent,
    max_workspace: workspace,
  })
}
