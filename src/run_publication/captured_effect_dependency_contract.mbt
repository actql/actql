///|
/// Integrity of selected Catalog bodies. Selection, current authority and
/// checked ownership are independently revalidated by the recovery owner.
/// Keep self-excluding contract identities distinct from member-body hashes.
pub fn admit_catalog_effect_dependency_body(
  kind : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  if !["source_contract", "source_view_contract", "data_policy"].contains(kind) {
    return Err(WrongDependencyKind)
  }
  let value = match parse_contract_wire(wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  if kind == "data_policy" &&
    [
      Some("actql-effective-data-policy/0.1"),
      Some("actql-source-response-policy/0.1"),
    ].contains(evidence_string(value, "version")) {
    return admit_checked_policy_effect_dependency(
      value, wire, max_bytes, max_nodes, max_depth,
    )
  }
  let (schema, self_field) = if kind == "data_policy" {
    ("actql.contract/0.1", "cid")
  } else {
    ("actql.source_view/0.1", "contract_cid")
  }
  if canonical_value_wire(value, max_bytes, max_nodes, max_depth) != Some(wire) ||
    evidence_string(value, "schema") != Some(schema) ||
    !evidence_identity_valid(value, self_field, max_bytes, max_nodes, max_depth) {
    return Err(InvalidBody)
  }
  if kind == "data_policy" &&
    evidence_string(value, "kind") != Some("data_policy") {
    return Err(WrongDependencyKind)
  }
  guard evidence_string(value, self_field) is Some(identity) else {
    return Err(InvalidBody)
  }
  // The complete selected body is retained. Its static Catalog closure is
  // validated by the same checked Check Environment, not a second registry.
  Ok({
    node: {
      kind,
      identity,
      canonical_bytes: @utf8.encode(wire).length(),
      references: [],
    },
    wire,
    value,
  })
}

///|
/// Existing checked policy preimages hash the whole body, unlike Catalog
/// envelopes. Retain their exact references; integrity is not authority.
fn admit_checked_policy_effect_dependency(
  value : @json.CanonicalValue,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  let effective = evidence_string(value, "version") ==
    Some("actql-effective-data-policy/0.1")
  let names = if effective {
    [
      "version", "classification", "source_data_policy_cids", "source_response_policy_cids",
      "unknown_provenance",
    ]
  } else {
    [
      "version", "classification", "source_ref", "source_view_contract_cid", "source_data_policy_cid",
      "minimum_classification",
    ]
  }
  guard object_fields(value) is Ok(fields) &&
    fields.length() == names.length() &&
    fields.all(entry => names.contains(entry.0)) &&
    canonical_value_wire(value, max_bytes, max_nodes, max_depth) == Some(wire) &&
    evidence_string(value, "classification") is Some(classification) &&
    ["public", "internal", "confidential", "restricted", "unknown"].contains(
      classification,
    ) else {
    return Err(InvalidBody)
  }
  let references : Array[CapturedEffectDependencyReference] = []
  if effective {
    guard @json.object_field(value, "unknown_provenance")
      is Some(@json.Bool(unknown)) else {
      return Err(InvalidBody)
    }
    if unknown && classification != "unknown" {
      return Err(InvalidBody)
    }
    for field in ["source_data_policy_cids", "source_response_policy_cids"] {
      guard dependency_list_references(value, field, "data_policy")
        is Some(items) else {
        return Err(InvalidBody)
      }
      let mut previous : String? = None
      for item in items {
        if previous is Some(prior) && prior >= item.identity {
          return Err(InvalidBody)
        }
        references.push(item)
        previous = Some(item.identity)
      }
    }
    if references.is_empty() && classification != "unknown" {
      return Err(InvalidBody)
    }
  } else {
    guard evidence_string(value, "source_ref") is Some(source) &&
      !source.is_empty() else {
      return Err(InvalidBody)
    }
    match @json.object_field(value, "minimum_classification") {
      Some(@json.Null) => ()
      Some(@json.String(minimum)) =>
        if !["public", "internal", "confidential", "restricted"].contains(
            minimum,
          ) {
          return Err(InvalidBody)
        }
      _ => return Err(InvalidBody)
    }
    for
      (field, target) in [
        ("source_data_policy_cid", "data_policy"),
        ("source_view_contract_cid", "source_view_contract"),
      ] {
      guard dependency_single_reference(value, field, target) is Some(reference) else {
        return Err(InvalidBody)
      }
      references.push(reference)
    }
  }
  let identity = @json.cid_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(InvalidBody)
  }
  Ok({
    node: {
      kind: "data_policy",
      identity,
      canonical_bytes: @utf8.encode(wire).length(),
      references,
    },
    wire,
    value,
  })
}
