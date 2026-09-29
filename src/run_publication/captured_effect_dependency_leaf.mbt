///|
/// Integrity admission for static checked projections and request values.
/// Their type/selection is attested by the existing checked owner separately;
/// an inventory token alone is neither that attestation nor execution authority.
/// These preimages have no self CID, so hash the complete canonical body.
pub fn admit_hashed_effect_dependency_body(
  kind : String,
  identity : String,
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectDependencyBody, CapturedEffectDependencyIssue] {
  if ![
      "local_body", "parameter_declarations", "used_values", "local_contracts", "local_policy",
      "result_import_type", "request_values", "schema_evidence", "capability_evidence",
      "relation_schema", "relation_value", "retention_contract", "metadata_retention_policy",
      "clock_contract",
    ].contains(kind) {
    return Err(WrongDependencyKind)
  }
  if !valid_contract_cid(identity) {
    return Err(InvalidBody)
  }
  let value = match parse_contract_wire(wire, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidBody)
  }
  let actual = @json.cid_value(value, max_bytes, max_nodes, max_depth) catch {
    _ => return Err(InvalidBody)
  }
  if canonical_value_wire(value, max_bytes, max_nodes, max_depth) != Some(wire) ||
    actual != identity {
    return Err(InvalidBody)
  }
  guard object_fields(value) is Ok(fields) else { return Err(InvalidBody) }
  let (version, names) : (String?, Array[String]) = match kind {
    "local_body" =>
      (
        Some("actql-stage-semantics/0.1"),
        [
          "version", "bindings", "binding_references", "parameters", "parameter_references",
          "expression_contract_cid", "local_body",
        ],
      )
    "used_values" => (Some("actql-parameter-values/0.1"), ["version", "values"])
    "local_contracts" =>
      (Some("actql-local-contracts/0.1"), ["version", "contracts"])
    "local_policy" => (Some("actql-capacity-host-policy/0.1"), [])
    "retention_contract" | "metadata_retention_policy" | "clock_contract" =>
      (Some("actql-installed-local-policy/0.1"), ["name", "version"])
    _ => (None, [])
  }
  if version is Some(expected) &&
    evidence_string(value, "version") != Some(expected) {
    return Err(InvalidBody)
  }
  if !names.is_empty() &&
    (
      fields.length() != names.length() ||
      !fields.all(entry => names.contains(entry.0))
    ) {
    return Err(InvalidBody)
  }
  if kind == "local_contracts" &&
    dependency_list_references(value, "contracts", "selected_contract") is None {
    return Err(InvalidBody)
  }
  if ["retention_contract", "metadata_retention_policy", "clock_contract"].contains(
      kind,
    ) {
    guard evidence_string(value, "name") is Some(name) && !name.is_empty() else {
      return Err(InvalidBody)
    }
  }
  // A logical Relation is not its physical ordered-row array. Both are
  // identified during export, but only this tagged preimage is referenced
  // by Source Input Logical and Result Artifact.
  if kind == "relation_value" {
    if fields.length() != 2 ||
      evidence_string(value, "sort") != Some("relation") ||
      !(@json.object_field(value, "value") is Some(@json.Array(_))) {
      return Err(InvalidBody)
    }
  }
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
