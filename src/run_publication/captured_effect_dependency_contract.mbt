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
