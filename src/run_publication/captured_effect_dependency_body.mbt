///|
/// Admitted dependency text and references extracted from its contract.
/// This token proves body integrity, not checked ownership or Store custody.
struct CapturedEffectDependencyBody {
  node : CapturedEffectDependencyNode
  wire : String
  value : @json.CanonicalValue
}

///|
fn dependency_single_reference(
  value : @json.CanonicalValue,
  field : String,
  kind : String,
) -> CapturedEffectDependencyReference? {
  guard evidence_string(value, field) is Some(identity) &&
    valid_contract_cid(identity) else {
    return None
  }
  Some({ kind, identity, })
}

///|
fn dependency_list_references(
  value : @json.CanonicalValue,
  field : String,
  kind : String,
) -> Array[CapturedEffectDependencyReference]? {
  guard @json.object_field(value, field) is Some(list) &&
    evidence_string_array(list) is Some(cids) else {
    return None
  }
  if !cids.all(valid_contract_cid) {
    return None
  }
  Some(cids.map(identity => { kind, identity, }))
}

///|
/// Read registered Publication bodies through their existing strict decoder.
/// Each edge below is derived from the admitted body, never an inventory
/// caller's claimed edge list. Other body families have separate admission.
pub fn admit_publication_effect_dependency_body(
  kind : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  if ![
      "result_artifact", "derivation_evidence", "ordering_evidence", "acquisition_relation",
      "acquisition_scope", "result_retention_policy",
    ].contains(kind) {
    return Err(WrongDependencyKind)
  }
  let contract = match
    admit_publication_contract(kind, wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  if contract.wire != wire {
    return Err(InvalidBody)
  }
  let value = contract.value
  let fields : Array[(String, String)] = match kind {
    "result_artifact" =>
      [
        ("result_definition_cid", "local_result_definition"),
        ("invocation_cid", "local_computation"),
        ("logical_result_cid", "relation_value"),
        ("result_schema_cid", "relation_schema"),
        ("ordering_evidence_cid", "ordering_evidence"),
        ("effective_data_policy_cid", "data_policy"),
        ("effective_retention_policy_cid", "result_retention_policy"),
      ]
    "derivation_evidence" =>
      [
        ("producer_contract_cid", "local_result_definition"),
        ("computation_contract_cid", "local_dependencies"),
        ("logical_value_cid", "relation_value"),
        ("relation_schema_cid", "relation_schema"),
        ("scope_cid", "acquisition_scope"),
        ("effective_data_policy_cid", "data_policy"),
      ]
    "acquisition_relation" =>
      [
        ("producer_contract_cid", "relation_producer"),
        ("logical_value_cid", "relation_value"),
        ("relation_schema_cid", "relation_schema"),
        ("ordering_evidence_cid", "ordering_evidence"),
        ("observation_scope_cid", "acquisition_scope"),
        ("effective_data_policy_cid", "data_policy"),
        ("effective_retention_policy_cid", "result_retention_policy"),
      ]
    "ordering_evidence" => [("producer_contract_cid", "relation_producer")]
    "result_retention_policy" =>
      [
        ("retention_contract_cid", "retention_contract"),
        ("effective_data_policy_cid", "data_policy"),
        ("metadata_retention_policy_cid", "metadata_retention_policy"),
        ("clock_contract_cid", "clock_contract"),
      ]
    _ => []
  }
  let references : Array[CapturedEffectDependencyReference] = []
  for (field, target) in fields {
    guard dependency_single_reference(value, field, target) is Some(reference) else {
      return Err(InvalidBody)
    }
    references.push(reference)
  }
  let lists : Array[(String, String)] = match kind {
    "result_artifact" => [("provenance_evidence_cids", "derivation_evidence")]
    "derivation_evidence" => [("input_relation_cids", "acquisition_relation")]
    _ => []
  }
  for (field, target) in lists {
    guard dependency_list_references(value, field, target) is Some(items) else {
      return Err(InvalidBody)
    }
    for item in items {
      references.push(item)
    }
  }
  let nested_field = match kind {
    "ordering_evidence" => Some("witness_evidence")
    "acquisition_relation" => Some("provenance_evidence")
    _ => None
  }
  if nested_field is Some(field) {
    guard @json.object_field(value, field) is Some(@json.Array(items)) else {
      return Err(InvalidBody)
    }
    for item in @json.array_values(items) {
      let target = match evidence_string(item, "kind") {
        Some("source") => "source_evidence"
        Some("derivation") => "derivation_evidence"
        Some("relation") => "acquisition_relation"
        Some("attempt_receipt") => "acquisition_attempt_receipt"
        _ => return Err(WrongDependencyKind)
      }
      guard dependency_single_reference(item, "cid", target) is Some(reference) else {
        return Err(InvalidBody)
      }
      references.push(reference)
    }
  }
  if kind == "acquisition_scope" {
    guard @json.object_field(value, "sources") is Some(@json.Array(items)) else {
      return Err(InvalidBody)
    }
    for item in @json.array_values(items) {
      guard dependency_single_reference(
          item, "source_contract_cid", "source_contract",
        )
        is Some(reference) else {
        return Err(InvalidBody)
      }
      references.push(reference)
      for
        (field, target) in [
          ("request_values_cid", "request_values"),
          ("request_key_set_cid", "request_key_set"),
        ] {
        if @json.object_field(item, field) is Some(@json.Null) {
          continue
        } else {
          guard dependency_single_reference(item, field, target)
            is Some(reference) else {
            return Err(InvalidBody)
          }
          references.push(reference)
        }
      }
    }
  }
  Ok({
    node: {
      kind,
      identity: contract.identity,
      canonical_bytes: @utf8.encode(wire).length(),
      references,
    },
    wire,
    value,
  })
}

///|
pub fn captured_effect_dependency_body_json(
  value : CapturedEffectDependencyBody,
) -> String {
  value.wire
}

///|
pub fn captured_effect_dependency_body_cid(
  value : CapturedEffectDependencyBody,
) -> String {
  value.node.identity
}

///|
pub fn captured_effect_dependency_body_kind(
  value : CapturedEffectDependencyBody,
) -> String {
  value.node.kind
}

///|
/// Source evidence retains the observation actually admitted by the Run.
/// Re-reading these bytes is not a new Source read or a current read grant.
pub fn source_effect_catalog_dependencies(
  evidence : RunEvidenceValue,
) -> Result[Array[(String, String)], CapturedEffectDependencyIssue] {
  if evidence.name != "source_evidence" {
    return Err(WrongDependencyKind)
  }
  let refs = []
  for
    (field, role) in [
      ("source_contract_cid", "source_contract"),
      ("schema_evidence_cid", "schema_evidence"),
      ("capability_evidence_cid", "capability_evidence"),
      ("source_data_policy_cid", "data_policy"),
      ("effective_data_policy_cid", "data_policy"),
      ("source_view_contract_cid", "source_view_contract"),
    ] {
    guard evidence_string(evidence.value, field) is Some(cid) else {
      return Err(InvalidBody)
    }
    refs.push((role, cid))
  }
  Ok(refs)
}

///|
pub fn admit_source_effect_dependency_body(
  kind : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  if kind != "source_input_logical" && kind != "source_evidence" {
    return Err(WrongDependencyKind)
  }
  let evidence = match
    admit_run_evidence_value(kind, wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  if evidence.wire != wire {
    return Err(InvalidBody)
  }
  let fields = if kind == "source_input_logical" {
    [
      ("logical_relation_cid", "relation_value"),
      ("relation_schema_cid", "relation_schema"),
      ("source_contract_cid", "source_contract"),
    ]
  } else {
    [
      ("input_logical_cid", "source_input_logical"),
      ("source_contract_cid", "source_contract"),
      ("schema_evidence_cid", "schema_evidence"),
      ("capability_evidence_cid", "capability_evidence"),
      ("source_data_policy_cid", "data_policy"),
      ("effective_data_policy_cid", "data_policy"),
      ("source_view_contract_cid", "source_view_contract"),
    ]
  }
  let references : Array[CapturedEffectDependencyReference] = []
  for (field, target) in fields {
    guard dependency_single_reference(evidence.value, field, target)
      is Some(reference) else {
      return Err(InvalidBody)
    }
    references.push(reference)
  }
  Ok({
    node: {
      kind,
      identity: evidence.identity,
      canonical_bytes: @utf8.encode(wire).length(),
      references,
    },
    wire,
    value: evidence.value,
  })
}

///|
pub fn admit_local_effect_dependency_body(
  kind : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  let (version, singles, lists, extra) : (
    String,
    Array[(String, String)],
    Array[(String, String)],
    Array[String],
  ) = match kind {
    "local_result_definition" =>
      (
        "actql-local-result-definition/0.1",
        [("unit_definition_cid", "local_dependencies")],
        [],
        ["result_name"],
      )
    "local_computation" =>
      (
        "actql-local-computation-semantics/0.1",
        [
          ("unit_definition_cid", "local_dependencies"),
          ("used_values_cid", "used_values"),
          ("local_contracts_cid", "local_contracts"),
          ("policy_cid", "local_policy"),
        ],
        [("observation_cids", "local_observation")],
        [],
      )
    "local_manifest" =>
      (
        "actql-local-result-manifest/0.1",
        [
          ("unit_definition_cid", "local_dependencies"),
          ("local_invocation_cid", "local_computation"),
        ],
        [],
        ["results"],
      )
    "result_import_observation" =>
      (
        "actql-result-import-observation/0.1",
        [
          ("consumer_unit_definition_cid", "local_dependencies"),
          ("import_interface_cid", "result_import_interface"),
          ("producer_local_manifest_cid", "local_manifest"),
          ("result_artifact_cid", "result_artifact"),
        ],
        [],
        ["input_name"],
      )
    "local_dependencies" =>
      (
        "actql-local-unit-dependencies/0.1",
        [
          ("local_body_cid", "local_body"),
          ("used_parameter_declarations_cid", "parameter_declarations"),
          ("local_contract_closure_cid", "local_contracts"),
        ],
        [
          ("import_interface_cids", "result_import_interface"),
          ("incoming_gate_contract_cids", "gate_requirement"),
        ],
        ["unit_namespace"],
      )
    "result_import_interface" =>
      (
        "actql-result-import-interface/0.1",
        [
          ("producer_unit_definition_cid", "local_dependencies"),
          ("value_contract_cid", "result_import_type"),
        ],
        [],
        ["input_name", "producer_namespace", "producer_result", "availability"],
      )
    "gate_requirement" =>
      (
        "actql-graph-success-requirement/0.1",
        [],
        [],
        [
          "completion_contracts", "completion_nodes", "effect_contracts", "effect_nodes",
          "empty_items", "milestone", "producer_node_id",
        ],
      )
    _ => return Err(WrongDependencyKind)
  }
  let value = match parse_contract_wire(wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  let fields = ["version", "self_cid"]
  for (field, _) in singles {
    fields.push(field)
  }
  for (field, _) in lists {
    fields.push(field)
  }
  for field in extra {
    fields.push(field)
  }
  if !exact_local_object(
      value, version, "self_cid", fields, max_bytes, max_nodes, max_depth,
    ) ||
    canonical_value_wire(value, max_bytes, max_nodes, max_depth) != Some(wire) {
    return Err(InvalidBody)
  }
  let references : Array[CapturedEffectDependencyReference] = []
  for (field, target) in singles {
    guard dependency_single_reference(value, field, target) is Some(reference) else {
      return Err(InvalidBody)
    }
    references.push(reference)
  }
  for (field, target) in lists {
    guard dependency_list_references(value, field, target) is Some(items) else {
      return Err(InvalidBody)
    }
    let seen : Map[String, Bool] = Map([])
    for item in items {
      if seen.contains(item.identity) {
        return Err(DuplicateIdentity)
      }
      seen[item.identity] = true
      references.push(item)
    }
  }
  for field in extra {
    if kind == "gate_requirement" &&
      [
        "completion_contracts", "completion_nodes", "effect_contracts", "effect_nodes",
      ].contains(field) {
      if !evidence_empty_object(@json.object_field(value, field)) {
        return Err(InvalidBody)
      }
    } else if field == "results" {
      guard @json.object_field(value, field) is Some(results) &&
        object_fields(results) is Ok(entries) &&
        !entries.is_empty() else {
        return Err(InvalidBody)
      }
      for (name, cid) in entries {
        guard !name.is_empty() &&
          optional_string(Some(cid)) is Some(identity) &&
          valid_contract_cid(identity) else {
          return Err(InvalidBody)
        }
        references.push({ kind: "result_artifact", identity, })
      }
    } else if field == "unit_namespace" || field == "producer_namespace" {
      guard @json.object_field(value, field) is Some(unit_namespace) &&
        object_fields(unit_namespace) is Ok(entries) &&
        entries.length() == 2 &&
        evidence_string(unit_namespace, "program_id") is Some(program) &&
        !program.is_empty() &&
        evidence_string(unit_namespace, "node_id") is Some(node) &&
        !node.is_empty() else {
        return Err(InvalidBody)
      }
    } else {
      guard evidence_string(value, field) is Some(text) && !text.is_empty() else {
        return Err(InvalidBody)
      }
      if field == "availability" && text != "stage_success" {
        return Err(InvalidBody)
      }
      if field == "empty_items" &&
        text != "require-successful-computation-and-preflight" {
        return Err(InvalidBody)
      }
      if field == "milestone" && text != "accepted" && text != "completed" {
        return Err(InvalidBody)
      }
    }
  }
  Ok({
    node: {
      kind,
      identity: evidence_string(value, "self_cid").unwrap(),
      canonical_bytes: @utf8.encode(wire).length(),
      references,
    },
    wire,
    value,
  })
}

///|
/// The selected checked roots and payload/static admissions are independent
/// obligations. A validated graph alone does not authorize Run recovery.
pub fn validate_captured_effect_dependency_bodies(
  bodies : Array[CapturedEffectDependencyBody],
  roots : Array[CapturedEffectDependencyBody],
  envelope_bytes : Int,
  limits : CapturedEffectDependencyLimits,
) -> Result[Unit, CapturedEffectDependencyIssue] {
  // Bound the index before allocating it. Full byte/edge/depth validation
  // follows, but a caller limit never permits an unbounded temporary map.
  if limits.max_entries < 0 || limits.max_entries > 4096 {
    return Err(InvalidLimits)
  }
  if bodies.length() > limits.max_entries || roots.length() > limits.max_entries {
    return Err(EntryLimit)
  }
  let kinds : Map[String, Array[String]] = Map([])
  for body in bodies {
    match kinds.get(body.node.identity) {
      Some(found) =>
        if !found.contains(body.node.kind) {
          found.push(body.node.kind)
        }
      None => kinds[body.node.identity] = [body.node.kind]
    }
  }
  let nodes : Array[CapturedEffectDependencyNode] = []
  for body in bodies {
    let references : Array[CapturedEffectDependencyReference] = []
    for reference in body.node.references {
      let allowed = match reference.kind {
        "relation_producer" => ["local_result_definition", "source_contract"]
        "local_observation" => ["source_evidence", "result_import_observation"]
        _ => []
      }
      if allowed.is_empty() {
        references.push(reference)
      } else {
        guard kinds.get(reference.identity) is Some(found) else {
          return Err(MissingDependency)
        }
        let candidates = found.filter(kind => allowed.contains(kind))
        if candidates.length() != 1 {
          return Err(WrongDependencyKind)
        }
        references.push({ kind: candidates[0], identity: reference.identity, })
      }
    }
    nodes.push({ ..body.node, references, })
  }
  match
    validate_captured_effect_dependency_graph(
      nodes,
      roots.map(value => {
        kind: value.node.kind,
        identity: value.node.identity,
      }),
      envelope_bytes,
      limits,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => validate_effect_dependency_import_bindings(bodies)
  }
}
