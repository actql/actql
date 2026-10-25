///|
// A metadata wire is already owned by its admitted original. UTF-8 occupies
// at most three bytes per UTF-16 code unit; every JSON value/container needs
// at least one byte. This fallback does not parse or copy the metadata wire.
fn capture_metadata_extent(wire : String) -> (Int64, Int64, Int64) {
  let bytes = wire.length().to_int64() * 3L
  (bytes, bytes, bytes)
}

///|
fn capture_contract_extent(
  value : PublicationContract,
) -> (Int64, Int64, Int64) {
  match value.wire_usage {
    Some((b, n, d)) => (b.to_int64(), n.to_int64(), d.to_int64())
    None => capture_metadata_extent(value.wire)
  }
}

///|
// Exact field names and empty container kinds mirror EffectContextPreparation;
// retaining the placeholders is conservative when adding the real children.
let capture_context_extent_skeleton : String =
  #|{"authoring_context":null,"effect_dependency_inventory":[],"effect_plan_logical_cids":{},"effect_plans":{},"effect_source_artifacts":{},"effect_source_holding_cids":{},"effect_source_local_inventory":{},"effects":{},"model_invocation_evidence":[],"model_invocation_evidence_cids":[],"pending_source_state_advances":[],"result_artifacts":{},"result_fields":{},"result_values":{},"version":"actql-run-effect-context/0.1"}

///|
let capture_outer_extent_skeleton : String =
  #|{"effect_context":null,"encryption_required":true,"receipt":null,"retention_class":"run-evidence","sensitivity":"private","version":"actql-captured-run/0.1"}

///|
// CID fields added by the two existing identity issuers; no new identity.
let capture_context_identity_extent : String =
  #|,"effect_context_cid":"sha256:0000000000000000000000000000000000000000000000000000000000000000"

///|
let capture_outer_identity_extent : String =
  #|,"captured_run_cid":"sha256:0000000000000000000000000000000000000000000000000000000000000000"

///|
fn captured_plain_run_construction_extent(
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
) -> CapturedRunConstructionExtent? {
  let (receipt_bytes, receipt_nodes, receipt_depth) = capture_contract_extent(
    receipt,
  )
  let (authoring_bytes, authoring_nodes, authoring_depth) = capture_metadata_extent(
    authoring.wire,
  )
  let mut bytes = capture_context_extent_skeleton.length().to_int64() +
    capture_outer_extent_skeleton.length().to_int64() +
    capture_context_identity_extent.length().to_int64() +
    capture_outer_identity_extent.length().to_int64() +
    receipt_bytes +
    authoring_bytes
  // Context root+15 fields; outer root+6 fields; two identity String values.
  let mut nodes = 16L + 7L + 2L + receipt_nodes + authoring_nodes
  let mut metadata_nodes = nodes
  let mut total_fields = 0L
  let mut max_fields = 0
  let mut depth = Int64::max(
    3L,
    Int64::max(receipt_depth + 1L, authoring_depth + 2L),
  )
  for snapshot in snapshots {
    if snapshot.row_wire_bytes < 2 ||
      snapshot.row_nodes < 1 ||
      snapshot.row_depth < 1 {
      return None
    }
    let (artifact_bytes, artifact_nodes, artifact_depth) = capture_contract_extent(
      snapshot.artifact,
    )
    // Three original occurrences: result_artifacts, result_fields, result_values.
    // Each map key uses quote/colon/comma plus escaped UTF-16 text.
    bytes += 3L * (4L + 6L * snapshot.name.length().to_int64()) +
      artifact_bytes +
      snapshot.row_wire_bytes.to_int64() +
      2L
    metadata_nodes += artifact_nodes + 1L + snapshot.fields.length().to_int64()
    total_fields += snapshot.fields.length().to_int64()
    max_fields = Int::max(max_fields, snapshot.fields.length())
    nodes += artifact_nodes + snapshot.row_nodes.to_int64() + 1L
    depth = Int64::max(
      depth,
      Int64::max(artifact_depth, snapshot.row_depth.to_int64()) + 3L,
    )
    for field in snapshot.fields {
      bytes += 3L + 6L * field.length().to_int64()
      nodes += 1L
    }
    if bytes > 2147483647L || nodes > 2147483647L || depth > 2147483647L {
      return None
    }
  }
  for model in models {
    let (b, n, d) = capture_metadata_extent(model.wire)
    bytes += b + 1L + 3L + 6L * model.identity.length().to_int64()
    nodes += n + 1L
    metadata_nodes += n + 1L
    depth = Int64::max(depth, d + 3L)
    if bytes > 2147483647L || nodes > 2147483647L || depth > 2147483647L {
      return None
    }
  }
  if bytes > 2147483647L || nodes > 2147483647L || depth > 2147483647L {
    return None
  }
  if metadata_nodes > 2147483647L || total_fields > 2147483647L {
    return None
  }
  Some({
    max_wire_bytes: bytes.to_int(),
    max_nodes: nodes.to_int(),
    max_depth: depth.to_int(),
    metadata_nodes: metadata_nodes.to_int(),
    results: snapshots.length(),
    total_fields: total_fields.to_int(),
    max_fields,
    models: models.length(),
  })
}

///|
fn captured_plain_run_extent(
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
) -> (Int, Int, Int)? {
  match
    captured_plain_run_construction_extent(
      receipt, snapshots, authoring, models,
    ) {
    Some(value) =>
      Some((value.max_wire_bytes, value.max_nodes, value.max_depth))
    None => None
  }
}

///|
/// Limits of this original preparation, not a separately supplied grant.
pub fn captured_run_preparation_limits(
  preparation : CapturedRunIssuancePreparation,
) -> (Int, Int, Int)? {
  if preparation.closed {
    return None
  }
  match preparation.inputs {
    Some(inputs) =>
      Some((inputs.max_wire_bytes, inputs.max_nodes, inputs.max_depth))
    None =>
      match preparation.completed {
        Some(original) =>
          Some(
            (original.max_wire_bytes, original.max_nodes, original.max_depth),
          )
        None => None
      }
  }
}

///|
/// Ordinary publication's nominal-input projection. The explicit-limit issuer
/// remains available unchanged for low-level bounded callers; both delegate
/// to the same preparation and semantic validation engine.
pub fn start_original_effect_free_captured_run(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  snapshots : Array[CapturedResultSnapshot],
  advances : Array[PendingSourceStateAdvance],
  authoring : RunEvidenceValue,
  models : Array[RunEvidenceValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
  content_generations? : Array[BoundContentGeneration] = [],
) -> CapturedRunIssuancePreparation {
  // Plain/current Model evidence has owned wire extents. Source advances and
  // generated Content still use their existing guarded issuer until their
  // original constructors expose extents; never infer those families as zero.
  let (max_wire_bytes, max_nodes, max_depth, max_workspace) = if advances.is_empty() &&
    content_generations.is_empty() {
    match captured_plain_run_extent(receipt, snapshots, authoring, models) {
      Some((b, n, d)) =>
        (b, n, d, Int::max(max_workspace, publication_evidence_workspace(n)))
      None => (0, 0, 0, max_workspace)
    }
  } else {
    (max_wire_bytes, max_nodes, max_depth, max_workspace)
  }
  start_effect_free_captured_run(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    snapshots,
    advances,
    authoring,
    models,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_workspace,
    content_generations~,
  )
}
