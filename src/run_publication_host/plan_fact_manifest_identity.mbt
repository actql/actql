///|
pub(all) enum PlanFactManifestIdentityIssue {
  InvalidBudget
  InvalidManifest
  InvalidPlanFacts
  FactMismatch
  CidMismatch
} derive(Eq, Debug)

///|
/// Canonical manifest identity. This value is not a checked fact set or Plan.
pub struct PlanFactManifestIdentity {
  wire : String
  cid : String
}

///|
pub fn plan_fact_manifest_identity_wire(
  value : PlanFactManifestIdentity,
) -> String {
  value.wire
}

///|
pub fn plan_fact_manifest_identity_cid(
  value : PlanFactManifestIdentity,
) -> String {
  value.cid
}

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
  // Identifier names in owner-emitted material have already been checked.
  // Re-admission must preserve JSON data keys nested inside typed cells.
  guard @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: max_wire_bytes,
      max_nodes,
      max_depth,
    })
    is Ok(source) else {
    return None
  }
  Some(
    @canonical.from_source(
      source,
      max_nodes,
      max_depth,
      max_wire_bytes,
      data_keys=true,
    ),
  ) catch {
    _ => None
  }
}

///|
/// Canonically encode an already owner-assembled Plan fact array. The caller
/// must separately prove that every required fact and consumer is present.
pub fn encode_plan_fact_manifest_identity(
  plan_facts_wire : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PlanFactManifestIdentity, PlanFactManifestIdentityIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidBudget)
  }
  guard parse_plan_identity_value(
      plan_facts_wire, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(plan_facts) else {
    return Err(InvalidPlanFacts)
  }
  let values = match plan_facts {
    @canonical.Array(values) => @canonical.array_values(values)
    _ => return Err(InvalidPlanFacts)
  }
  let encoded = prepare_plan_fact_manifest_facts(
    values, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(InvalidPlanFacts)
  }
  finish_plan_fact_manifest_identity(
    encoded, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
// One locally encoded array and its exact immutable children. Neither field
// escapes the synchronous issuer or establishes checked fact applicability.
priv struct EncodedPlanManifestFacts {
  wire : String
  values : Array[@canonical.CanonicalValue]
}

///|
fn prepare_plan_fact_manifest_facts(
  values : Array[@canonical.CanonicalValue],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> EncodedPlanManifestFacts raise @encode.EncodeFailure {
  let values = values.copy()
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
  @encode.begin_array(writer)
  for value in values {
    @canonical.emit_value(value, writer)
  }
  @encode.end_array(writer)
  { wire: @encode.finish(writer), values, }
}

///|
fn finish_plan_fact_manifest_identity(
  encoded : EncodedPlanManifestFacts,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PlanFactManifestIdentity, PlanFactManifestIdentityIssue] {
  let facts = encoded.wire
  let preimage = "{\"plan_facts\":" +
    facts +
    ",\"version\":\"actql-plan-fact-manifest/0.1\"}"
  let cid = "sha256:" + @sha.hex(@utf8.encode(preimage))
  let wire = "{\"plan_fact_manifest_cid\":\"" +
    cid +
    "\",\"plan_facts\":" +
    facts +
    ",\"version\":\"actql-plan-fact-manifest/0.1\"}"
  // Both strings were assembled here from this admitted immutable fact array.
  // Check the complete envelope's bounds without re-reading either string or
  // hashing its already-issued identity again. Saved input uses the reader below.
  try {
    let measure = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_plan_fact_manifest_body(
      measure,
      encoded.values,
      cid,
      @canonical.emit_value,
      (value, writer) => @encode.string_value(writer, value),
    )
    let _ = @encode.finish_measurement(measure)
    Ok({ wire, cid, })
  } catch {
    _ => Err(InvalidManifest)
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

///|
fn[T, C] emit_client_plan_fact_manifest_body(
  writer : @encode.Writer,
  values : Array[T],
  cid : C,
  emit_value : (T, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "plan_fact_manifest_cid")
  emit_cid(cid, writer)
  @encode.key(writer, "plan_facts")
  client_plan_emit_array(writer, values, emit_value)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-plan-fact-manifest/0.1")
  @encode.end_object(writer)
}
