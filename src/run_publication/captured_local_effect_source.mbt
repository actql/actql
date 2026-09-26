///|
/// The complete local semantic Result evidence embedded alongside one
/// Run-bound physical Effect source. It does not grant current Store access.
struct CapturedLocalEffectSourceEvidence {
  effect_id : String
  value : @json.CanonicalValue
}

///|
pub(all) enum CapturedLocalEffectSourceIssue {
  InvalidLocalContract(String)
  InvalidLocalReference(String)
  InvalidLocalResultEvidence
  InvalidPhysicalSource
  InvalidEncoding
} derive(Eq, Debug)

///|
fn exact_local_object(
  value : @json.CanonicalValue,
  version : String,
  identity_field : String,
  fields : Array[String],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  guard object_fields(value) is Ok(entries) &&
    entries.length() == fields.length() &&
    evidence_string(value, "version") == Some(version) &&
    evidence_identity_valid(
      value, identity_field, max_wire_bytes, max_nodes, max_depth,
    ) else {
    return false
  }
  for (name, _) in entries {
    if !fields.contains(name) {
      return false
    }
  }
  true
}

///|
fn admitted_nested_local_contract(
  value : @json.CanonicalValue,
  field : String,
  name : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> PublicationContract? {
  guard @json.object_field(value, field) is Some(nested) &&
    canonical_value_wire(nested, max_wire_bytes, max_nodes, max_depth)
    is Some(wire) else {
    return None
  }
  match
    admit_publication_contract(name, wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(contract) => Some(contract)
    Err(_) => None
  }
}

///|
fn validate_captured_local_effect_source_value(
  value : @json.CanonicalValue,
  physical : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, CapturedLocalEffectSourceIssue] {
  guard object_fields(value) is Ok(fields) && fields.length() == 7 else {
    return Err(InvalidLocalContract("inventory"))
  }
  for
    name in [
      "artifact", "definition", "derivation", "invocation", "manifest", "ordering",
      "retention",
    ] {
    if @json.object_field(value, name) is None {
      return Err(InvalidLocalContract(name))
    }
  }
  guard @json.object_field(value, "definition") is Some(definition) &&
    exact_local_object(
      definition,
      "actql-local-result-definition/0.1",
      "self_cid",
      ["version", "unit_definition_cid", "result_name", "self_cid"],
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) else {
    return Err(InvalidLocalContract("definition"))
  }
  guard @json.object_field(value, "invocation") is Some(invocation) &&
    exact_local_object(
      invocation,
      "actql-local-computation-semantics/0.1",
      "self_cid",
      [
        "version", "unit_definition_cid", "used_values_cid", "local_contracts_cid",
        "observation_cids", "policy_cid", "self_cid",
      ],
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) else {
    return Err(InvalidLocalContract("invocation"))
  }
  guard @json.object_field(value, "manifest") is Some(manifest) &&
    exact_local_object(
      manifest,
      "actql-local-result-manifest/0.1",
      "self_cid",
      [
        "version", "unit_definition_cid", "local_invocation_cid", "results", "self_cid",
      ],
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) else {
    return Err(InvalidLocalContract("manifest"))
  }
  guard evidence_string(definition, "self_cid") is Some(definition_cid) &&
    evidence_string(definition, "unit_definition_cid") is Some(unit_cid) &&
    valid_contract_cid(unit_cid) &&
    evidence_string(definition, "result_name") is Some(result_name) &&
    !result_name.is_empty() &&
    evidence_string(invocation, "self_cid") is Some(invocation_cid) &&
    evidence_string(invocation, "unit_definition_cid") == Some(unit_cid) &&
    evidence_string(manifest, "unit_definition_cid") == Some(unit_cid) &&
    evidence_string(manifest, "local_invocation_cid") == Some(invocation_cid) &&
    @json.object_field(manifest, "results") is Some(results) &&
    object_fields(results) is Ok(result_entries) &&
    !result_entries.is_empty() else {
    return Err(InvalidLocalReference("local_semantics"))
  }
  for (_, artifact_cid) in result_entries {
    guard string_value(artifact_cid) is Some(cid) && valid_contract_cid(cid) else {
      return Err(InvalidLocalReference("manifest.results"))
    }
  }
  guard admitted_nested_local_contract(
      value, "artifact", "result_artifact", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(artifact) &&
    admitted_nested_local_contract(
      value, "derivation", "derivation_evidence", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(derivation) &&
    admitted_nested_local_contract(
      value, "ordering", "ordering_evidence", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(ordering) &&
    admitted_nested_local_contract(
      value, "retention", "result_retention_policy", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(retention) else {
    return Err(InvalidLocalContract("result_evidence"))
  }
  if evidence_string(results, result_name) != Some(artifact.identity) ||
    contract_string(artifact, "result_definition_cid") != Some(definition_cid) ||
    contract_string(artifact, "invocation_cid") != Some(invocation_cid) {
    return Err(InvalidLocalReference("result_artifact"))
  }
  let evidence = match
    validate_result_occurrence_ordering_for_producer(
      definition_cid,
      derivation,
      ordering,
      contract_string(artifact, "logical_result_cid").unwrap_or(""),
      contract_string(artifact, "result_schema_cid").unwrap_or(""),
      contract_string(artifact, "effective_data_policy_cid").unwrap_or(""),
    ) {
    Ok(evidence) => evidence
    Err(_) => return Err(InvalidLocalResultEvidence)
  }
  if validate_local_result_artifact_evidence(
      definition_cid, artifact, evidence, retention,
    )
    is Err(_) {
    return Err(InvalidLocalResultEvidence)
  }
  if !effect_source_contract_matches_result_facts(
      physical, artifact, result_name,
    ) {
    return Err(InvalidPhysicalSource)
  }
  Ok(())
}

///|
pub fn admit_captured_local_effect_source(
  source : CapturedEffectSourceArtifact,
  definition_wire : String,
  invocation_wire : String,
  manifest_wire : String,
  artifact : PublicationContract,
  derivation : PublicationContract,
  ordering : PublicationContract,
  retention : PublicationContract,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedLocalEffectSourceEvidence, CapturedLocalEffectSourceIssue] {
  let definition = match
    parse_contract_wire(definition_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidLocalContract("definition"))
  }
  let invocation = match
    parse_contract_wire(invocation_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidLocalContract("invocation"))
  }
  let manifest = match
    parse_contract_wire(manifest_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidLocalContract("manifest"))
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(InvalidEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "artifact")
    @json.emit_value(artifact.value, writer)
    @encode.key(writer, "definition")
    @json.emit_value(definition, writer)
    @encode.key(writer, "derivation")
    @json.emit_value(derivation.value, writer)
    @encode.key(writer, "invocation")
    @json.emit_value(invocation, writer)
    @encode.key(writer, "manifest")
    @json.emit_value(manifest, writer)
    @encode.key(writer, "ordering")
    @json.emit_value(ordering.value, writer)
    @encode.key(writer, "retention")
    @json.emit_value(retention.value, writer)
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidEncoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(InvalidEncoding) }
  let value = match
    parse_contract_wire(wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(InvalidEncoding)
  }
  match
    validate_captured_local_effect_source_value(
      value,
      source.artifact,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  Ok({ effect_id: source.effect_id, value, })
}

///|
pub fn captured_local_effect_source_json(
  evidence : CapturedLocalEffectSourceEvidence,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String? {
  canonical_value_wire(evidence.value, max_wire_bytes, max_nodes, max_depth)
}
