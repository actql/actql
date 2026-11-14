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
      @json.object_field(source, "definition") is Some(definition) &&
      captured_local_definition_source(
        definition, max_bytes, max_nodes, max_depth,
      )
      is Some(relation_source) &&
      canonical_value_wire(artifact, max_bytes, max_nodes, max_depth)
      is Some(wire) else {
      return Err(InvalidBody)
    }
    let root = match
      admit_publication_effect_dependency_body(
        match relation_source {
          Result(_) => "result_artifact"
          TableInput(_) => "table_input_artifact"
        },
        wire,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let key = dependency_key(root.node.kind, root.node.identity)
    if !seen.contains(key) {
      seen[key] = true
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
  prepared? : CapturedEffectDependencyInventory? = None,
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
  if prepared is Some(original) {
    return original.wire == wire &&
      captured_effect_context_dependency_roots_match(
        context, original, max_bytes, max_nodes, max_depth,
      )
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

///|
// The body was already fully admitted. Compare actual captured root material
// with that typed body's canonical original, avoiding another parse/hash/graph.
pub fn captured_effect_context_dependency_roots_match(
  context : @json.CanonicalValue,
  inventory : CapturedEffectDependencyInventory,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard @json.object_field(context, "effect_source_local_inventory")
    is Some(sources) &&
    object_fields(sources) is Ok(sources) else {
    return false
  }
  captured_effect_dependency_source_values_match(
    ContextSources(sources),
    inventory,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
priv enum CapturedDependencySourceValues {
  ContextSources(Array[(String, @json.CanonicalValue)])
  AdmittedSources(Array[CapturedLocalEffectSourceEvidence])
}

///|
pub fn captured_effect_dependency_sources_match(
  sources : Array[CapturedLocalEffectSourceEvidence],
  inventory : CapturedEffectDependencyInventory,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  captured_effect_dependency_source_values_match(
    AdmittedSources(sources),
    inventory,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn captured_effect_dependency_source_values_match(
  sources : CapturedDependencySourceValues,
  inventory : CapturedEffectDependencyInventory,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  let expected : Map[String, CapturedEffectDependencyBody] = Map([])
  let found : Map[String, Bool] = Map([])
  for root in inventory.roots {
    expected[dependency_key(root.node.kind, root.node.identity)] = root
  }
  let count = match sources {
    ContextSources(values) => values.length()
    AdmittedSources(values) => values.length()
  }
  for index in 0..<count {
    let source = match sources {
      ContextSources(values) => values[index].1
      AdmittedSources(values) => values[index].value
    }
    guard @json.object_field(source, "invocation") is Some(invocation) &&
      @json.object_field(invocation, "observation_cids") is Some(observations) &&
      evidence_string_array(observations) is Some(observations) &&
      @json.object_field(source, "derivation") is Some(derivation) &&
      @json.object_field(derivation, "input_relation_cids") is Some(relations) &&
      evidence_string_array(relations) is Some(relations) else {
      return false
    }
    if observations.is_empty() && relations.is_empty() {
      continue
    }
    guard @json.object_field(source, "artifact") is Some(artifact) &&
      @json.object_field(source, "definition") is Some(definition) &&
      evidence_string(artifact, "result_artifact_cid") is Some(cid) else {
      return false
    }
    let kind = match evidence_string(definition, "version") {
      Some("actql-local-result-definition/0.1") => "result_artifact"
      Some("actql-local-table-input-definition/0.1") => "table_input_artifact"
      _ => return false
    }
    let key = dependency_key(kind, cid)
    guard expected.get(key) is Some(original) &&
      canonical_value_wire(artifact, max_bytes, max_nodes, max_depth) ==
      Some(original.wire) else {
      return false
    }
    found[key] = true
  }
  found.length() == expected.length()
}
