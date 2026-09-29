///|
fn effect_context_dependency_roots(
  local_sources : Array[@json.CanonicalValue],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[CapturedEffectDependencyBody], CapturedEffectDependencyIssue] {
  let roots : Array[CapturedEffectDependencyBody] = []
  let seen : Map[String, Bool] = Map([])
  for source in local_sources {
    guard @json.object_field(source, "invocation") is Some(invocation) &&
      @json.object_field(invocation, "observation_cids") is Some(observations) &&
      evidence_string_array(observations) is Some(observations) &&
      @json.object_field(source, "derivation") is Some(derivation) &&
      @json.object_field(derivation, "input_relation_cids") is Some(relations) &&
      evidence_string_array(relations) is Some(relations) else {
      return Err(InvalidBody)
    }
    // A Values root has no acquired/imported runtime dependency. Do not
    // manufacture a closure for that existing source-free capture.
    if observations.is_empty() && relations.is_empty() {
      continue
    }
    guard @json.object_field(source, "artifact") is Some(artifact) &&
      canonical_value_wire(artifact, max_bytes, max_nodes, max_depth)
      is Some(wire) else {
      return Err(InvalidBody)
    }
    let root = match
      admit_publication_effect_dependency_body(
        "result_artifact", wire, max_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !seen.contains(root.node.identity) {
      seen[root.node.identity] = true
      roots.push(root)
    }
  }
  Ok(roots)
}

///|
fn effect_context_dependency_limits(
  max_bytes : Int,
) -> CapturedEffectDependencyLimits {
  {
    max_entries: 4096,
    max_total_bytes: Int::min(max_bytes, 16777216),
    max_depth: 64,
    max_references: 65536,
  }
}

///|
/// The existing captured local source inventory, not caller-authored roots,
/// selects the exact dependency closure. Missing inventory is never repaired.
fn admit_effect_context_dependencies(
  local_sources : Array[@json.CanonicalValue],
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyInventory, CapturedEffectDependencyIssue] {
  let roots = match
    effect_context_dependency_roots(
      local_sources, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  admit_captured_effect_dependency_inventory(
    wire,
    roots,
    effect_context_dependency_limits(max_bytes),
    max_nodes,
    max_depth,
  )
}

///|
/// Adapter admission derives roots from exact captured local source tokens.
/// It cannot replace those roots with an adapter-supplied CID list.
pub fn admit_captured_effect_source_dependencies(
  sources : Array[CapturedLocalEffectSourceEvidence],
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyInventory, CapturedEffectDependencyIssue] {
  admit_effect_context_dependencies(
    sources.map(source => source.value),
    wire,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn captured_effect_context_dependencies_valid(
  context : @json.CanonicalValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard @json.object_field(context, "effect_source_local_inventory")
    is Some(local_sources) &&
    object_fields(local_sources) is Ok(entries) &&
    @json.object_field(context, "effect_dependency_inventory")
    is Some(inventory) &&
    canonical_value_wire(inventory, max_bytes, max_nodes, max_depth)
    is Some(wire) else {
    return false
  }
  admit_effect_context_dependencies(
    entries.map(entry => entry.1),
    wire,
    max_bytes,
    max_nodes,
    max_depth,
  )
  is Ok(_)
}
