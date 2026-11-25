///|
/// Admitted dependency text and references extracted from its contract.
/// This token proves body integrity, not checked ownership or Store custody.
struct CapturedEffectDependencyBody {
  node : CapturedEffectDependencyNode
  wire : String
  value : @json.CanonicalValue
  wire_usage : (Int, Int, Int)?
}

///|
/// Classification of the already checked effective policy, without a second
/// parse or a classification derived from the generated payload.
pub fn captured_effective_data_policy_classification(
  body : CapturedEffectDependencyBody,
) -> String? {
  guard body.node.kind == "data_policy" &&
    @json.object_field(body.value, "classification")
    is Some(@json.String(value)) else {
    return None
  }
  Some(value)
}

///|
/// Original final encoder facts of this same admitted body. These DATA are
/// neither permission nor a resource grant and do not traverse its tree.
pub fn captured_effect_dependency_body_wire_usage(
  body : CapturedEffectDependencyBody,
) -> (Int, Int, Int)? {
  body.wire_usage
}

///|
/// Exact canonical UTF-8 extent established by admission of this same body.
pub fn captured_effect_dependency_body_bytes(
  body : CapturedEffectDependencyBody,
) -> Int {
  body.node.canonical_bytes
}

///|
/// Borrow the bare rows of the same canonical Relation dependency. The
/// discarded wrapper contributes two nodes and one container level. Its
/// already-admitted UTF-8 extent bounds the bare rows' UTF-16 text budget.
pub fn captured_effect_dependency_relation_rows(
  body : CapturedEffectDependencyBody,
  logical_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @json.FrozenArray[@json.CanonicalValue]? {
  guard body.node.kind == "relation_value" &&
    body.node.identity == logical_cid &&
    body.wire_usage is Some((bytes, nodes, depth)) &&
    bytes <= max_bytes &&
    nodes - 2 <= max_nodes &&
    depth - 1 <= max_depth &&
    @json.object_field(body.value, "value") is Some(@json.Array(rows)) else {
    return None
  }
  Some(rows)
}

///|
/// Same admitted object width. Text length cannot supply this field count.
pub fn captured_effect_dependency_body_field_count(
  body : CapturedEffectDependencyBody,
) -> Int? {
  @json.object_field_count(body.value)
}

///|
/// Compare already admitted semantic fields with the original Model input.
/// This projection does not parse/hash either body again and does not attest
/// physical Model execution, an output holding, Store custody or permission.
pub fn local_model_observation_matches_input(
  body : CapturedEffectDependencyBody,
  unit_definition_cid : String,
  source_ordinal : Int,
  input : RunEvidenceValue,
) -> Bool {
  body.node.kind == "local_model_observation" &&
  input.name == "model_input_artifact" &&
  evidence_string(body.value, "unit_definition_cid") ==
  Some(unit_definition_cid) &&
  model_scope_count(body.value, "source_ordinal") ==
  Some(source_ordinal.to_int64()) &&
  evidence_string(input.value, "unit_definition_cid") ==
  Some(unit_definition_cid) &&
  model_scope_count(input.value, "source_ordinal") ==
  Some(source_ordinal.to_int64()) &&
  evidence_string(body.value, "input_logical_relation_cid") ==
  evidence_string(input.value, "logical_relation_cid") &&
  evidence_string(body.value, "input_relation_schema_cid") ==
  evidence_string(input.value, "relation_schema_cid")
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
  if is_lookup_effect_dependency_kind(kind) {
    return admit_lookup_effect_dependency_body(
      kind, wire, max_bytes, max_nodes, max_depth,
    )
  }
  if ![
      "result_artifact", "derivation_evidence", "ordering_evidence", "acquisition_relation",
      "acquisition_scope", "result_retention_policy", "table_input_artifact", "table_input_derivation",
      "table_input_ordering", "request_key_set",
    ].contains(kind) {
    return Err(WrongDependencyKind)
  }
  let contract_kind = match kind {
    "table_input_artifact" => "result_artifact"
    "table_input_derivation" => "derivation_evidence"
    "table_input_ordering" => "ordering_evidence"
    _ => kind
  }
  let contract = match
    admit_publication_contract(
      contract_kind, wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  if contract.wire != wire {
    return Err(InvalidBody)
  }
  publication_dependency_body_from_original(
    kind,
    contract,
    @utf8.encode(wire).length(),
    None,
  )
}

///|
/// Retain the SAME admitted Publication body and its derived reference roles.
/// No wire parsing, canonical serialization or CID hashing is repeated. This
/// proves only original body integrity, never current authority or custody.
pub fn capture_publication_effect_dependency_body(
  kind : String,
  contract : PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  if ![
      "result_artifact", "derivation_evidence", "ordering_evidence", "acquisition_relation",
      "acquisition_scope", "result_retention_policy", "table_input_artifact", "table_input_derivation",
      "table_input_ordering", "request_key_set",
    ].contains(kind) {
    return Err(WrongDependencyKind)
  }
  let expected = match kind {
    "table_input_artifact" => "result_artifact"
    "table_input_derivation" => "derivation_evidence"
    "table_input_ordering" => "ordering_evidence"
    _ => kind
  }
  if contract.name != expected {
    return Err(WrongDependencyKind)
  }
  guard publication_contract_check_limits(
      contract, max_bytes, max_nodes, max_depth,
    )
    is Ok(_) &&
    contract.wire_usage is Some(usage) else {
    return Err(InvalidBody)
  }
  publication_dependency_body_from_original(
    kind,
    contract,
    usage.0,
    Some(usage),
  )
}

///|
fn publication_dependency_body_from_original(
  kind : String,
  contract : PublicationContract,
  bytes : Int,
  usage : (Int, Int, Int)?,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  let wire = contract.wire
  let value = contract.value
  if kind == "request_key_set" {
    guard dependency_single_reference(
        value, "source_view_contract_cid", "source_view_contract",
      )
      is Some(source) &&
      dependency_single_reference(value, "request_schema_cid", "request_schema")
      is Some(schema) else {
      return Err(InvalidBody)
    }
    return Ok({
      node: {
        kind,
        identity: contract.identity,
        canonical_bytes: bytes,
        references: [source, schema],
      },
      wire,
      value,
      wire_usage: usage,
    })
  }
  let table = kind == "table_input_artifact" ||
    kind == "table_input_derivation" ||
    kind == "table_input_ordering"
  let producer_kind = if table {
    "local_table_input_definition"
  } else {
    "local_result_definition"
  }
  let derivation_kind = if table {
    "table_input_derivation"
  } else {
    "derivation_evidence"
  }
  let ordering_kind = if table {
    "table_input_ordering"
  } else {
    "ordering_evidence"
  }
  let fields : Array[(String, String)] = match kind {
    "result_artifact" | "table_input_artifact" =>
      [
        ("result_definition_cid", producer_kind),
        ("invocation_cid", "local_computation"),
        ("logical_result_cid", "relation_value"),
        ("result_schema_cid", "relation_schema"),
        ("ordering_evidence_cid", ordering_kind),
        ("effective_data_policy_cid", "data_policy"),
        ("effective_retention_policy_cid", "result_retention_policy"),
      ]
    "derivation_evidence" | "table_input_derivation" =>
      [
        (
          "producer_contract_cid",
          if table {
            producer_kind
          } else {
            "relation_producer"
          },
        ),
        (
          "computation_contract_cid",
          if table {
            "local_dependencies"
          } else {
            "relation_computation"
          },
        ),
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
    "table_input_ordering" => [("producer_contract_cid", producer_kind)]
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
    "result_artifact" | "table_input_artifact" =>
      [("provenance_evidence_cids", derivation_kind)]
    "derivation_evidence" | "table_input_derivation" =>
      [("input_relation_cids", "acquisition_relation")]
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
    "ordering_evidence" | "table_input_ordering" => Some("witness_evidence")
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
        Some("derivation") => derivation_kind
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
      canonical_bytes: bytes,
      references,
    },
    wire,
    value,
    wire_usage: usage,
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
/// Bounded metadata from the SAME admitted body's reference interpretation.
/// This neither resolves a Catalog nor attests current authority or custody.
pub fn captured_effect_dependency_body_references(
  value : CapturedEffectDependencyBody,
  max_references : Int,
) -> Array[(String, String)]? {
  if max_references < 0 || value.node.references.length() > max_references {
    return None
  }
  Some(
    value.node.references.map(reference => (reference.kind, reference.identity)),
  )
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
  source_dependency_body_from_original(
    evidence,
    @utf8.encode(wire).length(),
    None,
  )
}

///|
/// Borrow the same admitted Source observation/logical value. Historical DATA
/// and its strict reference roles remain separate from read/send permission.
pub fn capture_source_effect_dependency_body(
  evidence : RunEvidenceValue,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  if evidence.name != "source_input_logical" &&
    evidence.name != "source_evidence" {
    return Err(WrongDependencyKind)
  }
  guard evidence.wire_usage is Some((bytes, nodes, depth)) &&
    max_bytes > 0 &&
    max_nodes > 0 &&
    max_depth > 0 &&
    bytes <= max_bytes &&
    nodes <= max_nodes &&
    depth <= max_depth else {
    return Err(InvalidBody)
  }
  source_dependency_body_from_original(
    evidence,
    bytes,
    Some((bytes, nodes, depth)),
  )
}

///|
fn source_dependency_body_from_original(
  evidence : RunEvidenceValue,
  bytes : Int,
  usage : (Int, Int, Int)?,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  let kind = evidence.name
  let wire = evidence.wire
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
      canonical_bytes: bytes,
      references,
    },
    wire,
    value: evidence.value,
    wire_usage: usage,
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
    "local_table_input_definition" =>
      (
        "actql-local-table-input-definition/0.1",
        [("unit_definition_cid", "local_dependencies")],
        [],
        ["table_input_name"],
      )
    "local_model_observation" =>
      (
        "actql-local-model-observation/0.1",
        [
          ("unit_definition_cid", "local_dependencies"),
          ("input_logical_relation_cid", "relation_value"),
          ("input_relation_schema_cid", "relation_schema"),
          ("outcome_logical_relation_cid", "relation_value"),
          ("outcome_relation_schema_cid", "relation_schema"),
        ],
        [],
        ["source_ordinal"],
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
  let valid = if kind == "local_manifest" {
    captured_local_manifest_valid(value, max_bytes, max_nodes, max_depth)
  } else {
    exact_local_object(
      value, version, "self_cid", fields, max_bytes, max_nodes, max_depth,
    )
  }
  if !valid ||
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
    if kind == "local_model_observation" && field == "source_ordinal" {
      guard @json.object_field(value, field) is Some(@json.Number(raw)) &&
        @scalar.read_safe_integer(raw) is Some(ordinal) &&
        ordinal >= 0L &&
        ordinal < 2147483647L else {
        return Err(InvalidBody)
      }
    } else if kind == "gate_requirement" &&
      [
        "completion_contracts", "completion_nodes", "effect_contracts", "effect_nodes",
      ].contains(field) {
      if !evidence_empty_object(@json.object_field(value, field)) {
        return Err(InvalidBody)
      }
    } else if field == "results" {
      guard @json.object_field(value, field) is Some(results) &&
        object_fields(results) is Ok(entries) else {
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
  if kind == "local_manifest" &&
    @json.object_field(value, "table_inputs") is Some(private_map) {
    guard object_fields(private_map) is Ok(entries) else {
      return Err(InvalidBody)
    }
    for (_, cid) in entries {
      guard string_value(cid) is Some(identity) else { return Err(InvalidBody) }
      references.push({ kind: "table_input_artifact", identity, })
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
    wire_usage: None,
  })
}

///|
/// The selected checked roots and payload/static admissions are independent
/// obligations. A validated graph alone does not authorize Run recovery.
fn validate_selected_captured_effect_dependency_bodies(
  bodies : Array[CapturedEffectDependencyBody],
  roots : Array[CapturedEffectDependencyBody],
  envelope_bytes : Int,
  limits : CapturedEffectDependencyLimits,
  prepared? : Bool = false,
  work? : ((Int) -> Bool)? = None,
) -> Result[Unit, CapturedEffectDependencyIssue] {
  // Bound the index before allocating it. Full byte/edge/depth validation
  // follows, but a caller limit never permits an unbounded temporary map.
  if limits.max_entries < 0 || (!prepared && limits.max_entries > 4096) {
    return Err(InvalidLimits)
  }
  if bodies.length() > limits.max_entries || roots.length() > limits.max_entries {
    return Err(EntryLimit)
  }
  let kinds : Map[String, Array[String]] = Map([])
  for body in bodies {
    if !dependency_validation_work(work, 1) ||
      !dependency_validation_work(work, body.node.identity.length()) {
      return Err(ReferenceLimit)
    }
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
    if !dependency_validation_work(work, 1) ||
      !dependency_validation_work(work, body.node.identity.length()) {
      return Err(ReferenceLimit)
    }
    let references : Array[CapturedEffectDependencyReference] = []
    for reference in body.node.references {
      if !dependency_validation_work(work, 1) ||
        !dependency_validation_work(work, reference.identity.length()) {
        return Err(ReferenceLimit)
      }
      let allowed = match reference.kind {
        "read_execution_profile" =>
          [
            "native_file_content_read", "declared_file_content_read", "installed_row_source_read",
          ]
        "relation_producer" =>
          [
            "local_result_definition", "source_contract", "carrier_contract", "relation_schema",
          ]
        "relation_computation" =>
          ["local_dependencies", "task_fragment", "lookup_barrier"]
        "relation_carrier" => ["carrier_contract", "relation_schema"]
        "local_observation" =>
          [
            "source_evidence", "result_import_observation", "local_model_observation",
            "lookup_evidence",
          ]
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
      prepared~,
      work~,
    ) {
    Err(issue) => Err(issue)
    Ok(_) =>
      validate_effect_dependency_import_bindings(bodies, prepared~, work~)
  }
}

///|
// The normal public envelope remains fixed. Only the closed funded issuer/
// reader inside this package selects the prepared semantic extent above.
pub fn validate_captured_effect_dependency_bodies(
  bodies : Array[CapturedEffectDependencyBody],
  roots : Array[CapturedEffectDependencyBody],
  envelope_bytes : Int,
  limits : CapturedEffectDependencyLimits,
) -> Result[Unit, CapturedEffectDependencyIssue] {
  validate_selected_captured_effect_dependency_bodies(
    bodies, roots, envelope_bytes, limits,
  )
}

///|
pub fn captured_effect_dependency_body_reference_count(
  value : CapturedEffectDependencyBody,
) -> Int {
  value.node.references.length()
}

///|
// Borrow one already admitted semantic edge without copying the reference
// vector. The closed original caller prepays controls and visits.
pub fn captured_effect_dependency_body_reference_at(
  value : CapturedEffectDependencyBody,
  index : Int,
) -> (String, String)? {
  value.node.references
  .get(index)
  .map(reference => (reference.kind, reference.identity))
}
