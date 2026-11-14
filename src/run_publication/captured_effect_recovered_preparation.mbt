///|
// Immutable semantic DATA from one authenticated captured Run. The Request
// caller backs every constructor before entry. This is no Read/current grant.
struct PreparedCapturedEffectRun {
  captured : PublicationContract
  inventory : CapturedEffectDependencyInventory
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
/// Bind already admitted immutable inventory to this exact completed capture.
/// The closed original constructor backs the one encoder/compare first. No
/// graph/body admission or physical/current authority is repeated here.
pub fn bind_prepared_captured_effect_run(
  captured : PublicationContract,
  inventory : CapturedEffectDependencyInventory,
) -> Result[PreparedCapturedEffectRun, CapturedEffectDependencyIssue] {
  guard captured.name == "captured_run" &&
    captured.wire_usage is Some((max_bytes, max_nodes, max_depth)) &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "effect_dependency_inventory") is Some(value) &&
    canonical_value_wire(value, max_bytes, max_nodes, max_depth) ==
    Some(inventory.wire) &&
    captured_effect_context_dependency_roots_match(
      context, inventory, max_bytes, max_nodes, max_depth,
    ) else {
    return Err(InvalidBody)
  }
  Ok({ captured, inventory, max_bytes, max_nodes, max_depth, })
}

///|
pub fn prepare_recovered_captured_effect_run(
  captured : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  work : (Int) -> Bool,
) -> Result[PreparedCapturedEffectRun, CapturedEffectDependencyIssue] {
  guard captured.name == "captured_run" &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "effect_source_local_inventory")
    is Some(sources) &&
    object_fields(sources) is Ok(sources) &&
    @json.object_field(context, "effect_dependency_inventory") is Some(value) &&
    value is @json.Array(entries) else {
    return Err(InvalidBody)
  }
  if !work(sources.length()) || !work(@json.array_count(entries)) {
    return Err(ReferenceLimit)
  }
  let roots = match
    effect_context_dependency_roots(
      sources.map(pair => pair.1),
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard canonical_value_wire(value, max_bytes, max_nodes, max_depth)
    is Some(wire) else {
    return Err(InvalidBody)
  }
  let limits : CapturedEffectDependencyLimits = {
    // Actual semantic array inventory; byte/node observations never become
    // an entry allowance. All family/depth/reference rules remain unchanged.
    max_entries: Int::max(@json.array_count(entries), roots.length()),
    max_total_bytes: max_bytes,
    max_depth: 64,
    max_references: 65536,
  }
  let inventory = match
    admit_captured_effect_dependency_inventory_material(
      value,
      wire,
      roots,
      limits,
      max_nodes,
      max_depth,
      prepared=true,
      work=Some(work),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  Ok({ captured, inventory, max_bytes, max_nodes, max_depth, })
}

///|
pub fn prepared_captured_effect_run_contract(
  value : PreparedCapturedEffectRun,
) -> PublicationContract {
  value.captured
}

///|
pub fn prepared_captured_effect_run_inventory(
  value : PreparedCapturedEffectRun,
) -> CapturedEffectDependencyInventory {
  value.inventory
}

///|
pub fn prepared_captured_effect_run_limits(
  value : PreparedCapturedEffectRun,
) -> (Int, Int, Int) {
  (value.max_bytes, value.max_nodes, value.max_depth)
}

///|
pub fn validate_prepared_effectful_computation_evidence_chain(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured : PublicationContract,
  prepared : PreparedCapturedEffectRun,
  preview : EffectPreviewIdentity,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, RunEvidenceChainIssue] {
  if !physical_equal(captured, prepared.captured) {
    return Err(EvidenceInventoryMismatch("effect_dependency_inventory"))
  }
  validate_computation_run_evidence_chain(
    run_definition,
    invocation,
    definitions,
    artifacts,
    manifest,
    receipt,
    captured,
    Some(preview),
    Int::max(max_bytes, prepared.max_bytes),
    Int::max(max_nodes, prepared.max_nodes),
    Int::max(max_depth, prepared.max_depth),
    dependency_inventory=Some(prepared.inventory),
  )
}

///|
pub fn prepared_captured_effect_run_schemas(
  value : PreparedCapturedEffectRun,
) -> Array[(String, String)] {
  let schemas = []
  for body in value.inventory.bodies {
    if body.node.kind == "relation_schema" {
      schemas.push((body.node.identity, body.wire))
    }
  }
  schemas
}

///|
pub fn prepared_captured_effect_run_payloads(
  value : PreparedCapturedEffectRun,
) -> Array[String] {
  let identities = []
  for body in value.inventory.bodies {
    if body.node.kind == "result_artifact" ||
      body.node.kind == "table_input_artifact" {
      identities.push(body.node.identity)
    }
  }
  identities
}
