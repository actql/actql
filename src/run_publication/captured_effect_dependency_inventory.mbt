///|
/// Canonical, closed dependency envelope. Issuance and recovery share the
/// same body/graph checks; this alone is not an execution or custody permit.
struct CapturedEffectDependencyInventory {
  bodies : Array[CapturedEffectDependencyBody]
  wire : String
}

///|
/// One shared body dispatch for issuance and saved inventory admission.
/// Hash-only bodies require the identity established by the retained owner;
/// self-identifying bodies may omit it, but cannot contradict a supplied CID.
pub fn admit_captured_effect_dependency_body(
  kind : String,
  identity : String?,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  let result = if [
      "local_result_definition", "local_computation", "local_manifest", "result_import_observation",
      "local_dependencies", "result_import_interface", "gate_requirement",
    ].contains(kind) {
    admit_local_effect_dependency_body(
      kind, wire, max_bytes, max_nodes, max_depth,
    )
  } else if ["source_contract", "source_view_contract", "data_policy"].contains(
      kind,
    ) {
    admit_catalog_effect_dependency_body(
      kind, wire, max_bytes, max_nodes, max_depth,
    )
  } else if kind == "source_input_logical" || kind == "source_evidence" {
    admit_source_effect_dependency_body(
      kind, wire, max_bytes, max_nodes, max_depth,
    )
  } else if [
      "local_body", "parameter_declarations", "used_values", "local_contracts", "local_policy",
      "result_import_type", "request_values", "schema_evidence", "capability_evidence",
      "relation_schema", "relation_value", "retention_contract", "metadata_retention_policy",
      "clock_contract",
    ].contains(kind) {
    guard identity is Some(cid) else { return Err(InvalidBody) }
    admit_hashed_effect_dependency_body(
      kind, cid, wire, max_bytes, max_nodes, max_depth,
    )
  } else {
    admit_publication_effect_dependency_body(
      kind, wire, max_bytes, max_nodes, max_depth,
    )
  }
  let body = match result {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if identity is Some(cid) && body.node.identity != cid {
    return Err(InvalidBody)
  }
  Ok(body)
}

///|
fn dependency_inventory_limits_valid(
  limits : CapturedEffectDependencyLimits,
) -> Bool {
  limits.max_entries >= 0 &&
  limits.max_entries <= 4096 &&
  limits.max_total_bytes > 0 &&
  limits.max_total_bytes <= 16777216 &&
  limits.max_depth > 0 &&
  limits.max_depth <= 64 &&
  limits.max_references >= 0 &&
  limits.max_references <= 65536
}

///|
fn dependency_inventory_validate_size(
  bodies : Array[CapturedEffectDependencyBody],
  roots : Array[CapturedEffectDependencyBody],
  wire_bytes : Int,
  limits : CapturedEffectDependencyLimits,
) -> Result[Unit, CapturedEffectDependencyIssue] {
  if wire_bytes > limits.max_total_bytes {
    return Err(ByteLimit)
  }
  let mut envelope = wire_bytes
  for body in bodies {
    if body.node.canonical_bytes > envelope {
      return Err(InvalidBody)
    }
    envelope -= body.node.canonical_bytes
  }
  validate_captured_effect_dependency_bodies(bodies, roots, envelope, limits)
}

///|
pub fn issue_captured_effect_dependency_inventory(
  bodies : Array[CapturedEffectDependencyBody],
  roots : Array[CapturedEffectDependencyBody],
  limits : CapturedEffectDependencyLimits,
  max_nodes : Int,
  max_json_depth : Int,
) -> Result[CapturedEffectDependencyInventory, CapturedEffectDependencyIssue] {
  if !dependency_inventory_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  match validate_captured_effect_dependency_bodies(bodies, roots, 0, limits) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let ordered = bodies.copy()
  ordered.sort_by(fn(a, b) {
    let compared = @canonical.compare_utf16(a.node.identity, b.node.identity)
    if compared == 0 {
      @canonical.compare_utf16(a.node.kind, b.node.kind)
    } else {
      compared
    }
  })
  let writer = @encode.writer(limits.max_total_bytes, max_nodes, max_json_depth) catch {
    _ => return Err(InvalidLimits)
  }
  try {
    @encode.begin_array(writer)
    for body in ordered {
      let value = match
        parse_contract_wire(
          body.wire,
          limits.max_total_bytes,
          max_nodes,
          max_json_depth,
        ) {
        Ok(value) => value
        Err(_) => return Err(InvalidBody)
      }
      @encode.begin_object(writer)
      @encode.key(writer, "body")
      @json.emit_value(value, writer)
      @encode.key(writer, "cid")
      @encode.string_value(writer, body.node.identity)
      @encode.key(writer, "kind")
      @encode.string_value(writer, body.node.kind)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
  } catch {
    _ => return Err(ByteLimit)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(ByteLimit) }
  match
    dependency_inventory_validate_size(
      ordered,
      roots,
      @utf8.encode(wire).length(),
      limits,
    ) {
    Ok(_) => Ok({ bodies: ordered, wire, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn admit_captured_effect_dependency_inventory(
  wire : String,
  roots : Array[CapturedEffectDependencyBody],
  limits : CapturedEffectDependencyLimits,
  max_nodes : Int,
  max_json_depth : Int,
) -> Result[CapturedEffectDependencyInventory, CapturedEffectDependencyIssue] {
  if !dependency_inventory_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let value = match
    parse_contract_wire(wire, limits.max_total_bytes, max_nodes, max_json_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  if canonical_value_wire(
      value,
      limits.max_total_bytes,
      max_nodes,
      max_json_depth,
    ) !=
    Some(wire) {
    return Err(InvalidBody)
  }
  guard value is @json.Array(entries) else { return Err(InvalidBody) }
  let entries = @json.array_values(entries)
  if entries.length() > limits.max_entries {
    return Err(EntryLimit)
  }
  let bodies : Array[CapturedEffectDependencyBody] = []
  let mut previous = ""
  let mut previous_kind = ""
  for entry in entries {
    guard object_fields(entry) is Ok(fields) &&
      fields.length() == 3 &&
      evidence_string(entry, "kind") is Some(kind) &&
      evidence_string(entry, "cid") is Some(identity) &&
      @json.object_field(entry, "body") is Some(body) &&
      canonical_value_wire(
        body,
        limits.max_total_bytes,
        max_nodes,
        max_json_depth,
      )
      is Some(body_wire) else {
      return Err(InvalidBody)
    }
    if !valid_contract_cid(identity) {
      return Err(InvalidBody)
    }
    if previous == identity && previous_kind == kind {
      return Err(DuplicateIdentity)
    }
    if !previous.is_empty() &&
      (
        @canonical.compare_utf16(previous, identity) > 0 ||
        (
          previous == identity &&
          @canonical.compare_utf16(previous_kind, kind) >= 0
        )
      ) {
      return Err(InvalidBody)
    }
    previous = identity
    previous_kind = kind
    let admitted = admit_captured_effect_dependency_body(
      kind,
      Some(identity),
      body_wire,
      limits.max_total_bytes,
      max_nodes,
      max_json_depth,
    )
    let admitted = match admitted {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if admitted.node.identity != identity {
      return Err(InvalidBody)
    }
    bodies.push(admitted)
  }
  match
    dependency_inventory_validate_size(
      bodies,
      roots,
      @utf8.encode(wire).length(),
      limits,
    ) {
    Ok(_) => Ok({ bodies, wire, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn captured_effect_dependency_inventory_json(
  inventory : CapturedEffectDependencyInventory,
) -> String {
  inventory.wire
}

///|
pub fn captured_effect_dependency_inventory_count(
  inventory : CapturedEffectDependencyInventory,
) -> Int {
  inventory.bodies.length()
}
