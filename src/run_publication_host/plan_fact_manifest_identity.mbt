///|
pub(all) enum PlanFactManifestIdentityIssue {
  InvalidBudget
  InvalidManifest
  InvalidPlanFacts
  FactMismatch
  CidMismatch
} derive(Eq, Debug)

///|
fn parse_plan_identity_value(
  body : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @canonical.CanonicalValue? {
  let bytes = @utf8.encode(body)
  if bytes.length() > max_wire_bytes {
    return None
  }
  guard @source.parse_json_bytes(bytes, {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    })
    is Ok(source) else {
    return None
  }
  Some(@canonical.from_source(source, max_nodes, max_depth, max_wire_bytes)) catch {
    _ => None
  }
}

///|
/// Check one saved manifest's canonical identity and exact Plan fact array.
/// This proves neither fact completeness nor the Plan's execution authority.
pub fn check_plan_fact_manifest_identity(
  manifest_wire : String,
  plan_facts_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, PlanFactManifestIdentityIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidBudget)
  }
  guard parse_plan_identity_value(
      manifest_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(manifest) else {
    return Err(InvalidManifest)
  }
  guard parse_plan_identity_value(
      plan_facts_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(plan_facts) else {
    return Err(InvalidPlanFacts)
  }
  guard plan_facts is @canonical.Array(_) else { return Err(InvalidPlanFacts) }
  guard @canonical.object_fields(manifest) is Some(fields) &&
    fields.length() == 3 else {
    return Err(InvalidManifest)
  }
  guard @canonical.object_field(manifest, "version")
    is Some(@canonical.String("actql-plan-fact-manifest/0.1")) else {
    return Err(InvalidManifest)
  }
  guard @canonical.object_field(manifest, "plan_facts") is Some(manifest_facts) else {
    return Err(InvalidManifest)
  }
  guard manifest_facts is @canonical.Array(_) else {
    return Err(InvalidManifest)
  }
  guard @canonical.object_field(manifest, "plan_fact_manifest_cid")
    is Some(@canonical.String(claimed_cid)) else {
    return Err(InvalidManifest)
  }
  let saved_facts = @canonical.stringify_value(
    manifest_facts, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidManifest)
  }
  let current_facts = @canonical.stringify_value(
    plan_facts, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidPlanFacts)
  }
  if saved_facts != current_facts {
    return Err(FactMismatch)
  }
  guard @canonical.object_without_field(manifest, "plan_fact_manifest_cid")
    is Some(preimage) else {
    return Err(InvalidManifest)
  }
  let actual_cid = @canonical.cid_value(
    preimage, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidManifest)
  }
  if claimed_cid != actual_cid {
    return Err(CidMismatch)
  }
  Ok(actual_cid)
}
