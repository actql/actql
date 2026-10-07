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
/// A private producer has its own closed version and name slot. Equal name
/// text or Artifact shape never changes an ordinary Result into a Table input.
fn captured_local_definition_source(
  definition : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> EffectPreviewRelationSource? {
  let (version, name_field, table) = match
    evidence_string(definition, "version") {
    Some("actql-local-result-definition/0.1") =>
      ("actql-local-result-definition/0.1", "result_name", false)
    Some("actql-local-table-input-definition/0.1") =>
      ("actql-local-table-input-definition/0.1", "table_input_name", true)
    _ => return None
  }
  guard exact_local_object(
      definition,
      version,
      "self_cid",
      ["version", "unit_definition_cid", name_field, "self_cid"],
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) &&
    evidence_string(definition, "unit_definition_cid") is Some(unit) &&
    valid_contract_cid(unit) &&
    evidence_string(definition, name_field) is Some(name) &&
    !name.is_empty() else {
    return None
  }
  Some(if table { TableInput(name) } else { Result(name) })
}

///|
/// Validate both namespaces before using either map. Private-only Manifests
/// may have no public Results, but an empty private map is not an extension.
fn captured_local_manifest_valid(
  manifest : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  let fields = [
    "version", "unit_definition_cid", "local_invocation_cid", "results", "self_cid",
  ]
  let private_map = @json.object_field(manifest, "table_inputs")
  if private_map is Some(_) {
    fields.push("table_inputs")
  }
  guard exact_local_object(
      manifest, "actql-local-result-manifest/0.1", "self_cid", fields, max_wire_bytes,
      max_nodes, max_depth,
    ) &&
    @json.object_field(manifest, "results") is Some(results) &&
    object_fields(results) is Ok(entries) else {
    return false
  }
  let private_entries = match private_map {
    None => []
    Some(map) => {
      guard object_fields(map) is Ok(items) && !items.is_empty() else {
        return false
      }
      items
    }
  }
  if entries.is_empty() && private_entries.is_empty() {
    return false
  }
  for map in [entries, private_entries] {
    for (name, value) in map {
      guard !name.is_empty() &&
        string_value(value) is Some(cid) &&
        valid_contract_cid(cid) else {
        return false
      }
    }
  }
  true
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
    captured_local_definition_source(
      definition, max_wire_bytes, max_nodes, max_depth,
    )
    is Some(source) else {
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
    captured_local_manifest_valid(
      manifest, max_wire_bytes, max_nodes, max_depth,
    ) else {
    return Err(InvalidLocalContract("manifest"))
  }
  guard evidence_string(definition, "self_cid") is Some(definition_cid) &&
    evidence_string(definition, "unit_definition_cid") is Some(unit_cid) &&
    valid_contract_cid(unit_cid) &&
    evidence_string(invocation, "self_cid") is Some(invocation_cid) &&
    evidence_string(invocation, "unit_definition_cid") == Some(unit_cid) &&
    evidence_string(manifest, "unit_definition_cid") == Some(unit_cid) &&
    evidence_string(manifest, "local_invocation_cid") == Some(invocation_cid) else {
    return Err(InvalidLocalReference("local_semantics"))
  }
  let (map_name, name) = match source {
    Result(name) => ("results", name)
    TableInput(name) => ("table_inputs", name)
  }
  guard @json.object_field(manifest, map_name) is Some(results) else {
    return Err(InvalidLocalReference("manifest." + map_name))
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
  if evidence_string(results, name) != Some(artifact.identity) ||
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
  if !effect_source_contract_matches_relation_facts(physical, artifact, source) {
    return Err(InvalidPhysicalSource)
  }
  Ok(())
}

///|
/// A source member can name either its physical contract or its embedded
/// semantic Result. Both references require the complete local evidence;
/// neither changes the physical holding identity or grants Store access.
fn captured_local_effect_source_matches_preview(
  preview : EffectPreviewIdentity,
  member_index : Int,
  physical : PublicationContract,
  local_value : @json.CanonicalValue,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  if validate_captured_local_effect_source_value(
      local_value, physical, max_wire_bytes, max_nodes, max_depth,
    )
    is Err(_) {
    return false
  }
  guard effect_preview_member_result_artifact_cid(preview, member_index)
    is Some(expected) &&
    effect_source_artifact_relation_source(physical) ==
    effect_preview_member_relation_source(preview, member_index) else {
    return false
  }
  if expected == physical.identity {
    return true
  }
  guard admitted_nested_local_contract(
      local_value, "artifact", "result_artifact", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(result) else {
    return false
  }
  expected == result.identity
}

///|
pub fn captured_effect_source_matches_preview(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  source : CapturedEffectSourceArtifact,
  local_evidence : CapturedLocalEffectSourceEvidence,
  store_authority_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  if local_evidence.effect_id != source.effect_id ||
    !captured_local_effect_source_matches_preview(
      preview,
      member_index,
      source.artifact,
      local_evidence.value,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    return false
  }
  guard effect_preview_member_result_artifact_cid(preview, member_index)
    is Some(expected) &&
    admit_captured_effect_source_binding(
      preview,
      member_index,
      invocation,
      source.artifact,
      expected,
      store_authority_cid,
    )
    is Ok(admitted) else {
    return false
  }
  admitted.effect_id == source.effect_id &&
  admitted.holding_cid == source.holding_cid
}

///|
/// Restore the exact source from the admitted capture inventory. The caller
/// separately validates the complete Run chain and reconciles the physical
/// Store holding; this admission is not custody, permission or a fresh send.
pub fn admit_captured_effect_source_from_capture(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  artifact : PublicationContract,
  captured : PublicationContract,
  store_authority_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[CapturedEffectSourceArtifact, CapturedRunIssuanceIssue] {
  guard captured.name == "captured_run" &&
    invocation.name == "run_invocation" &&
    effect_preview_member_effect_id(preview, member_index) is Some(effect_id) &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    evidence_identity_valid(
      context, "effect_context_cid", max_wire_bytes, max_nodes, max_depth,
    ) &&
    effect_context_preview_inventory_matches(
      context,
      preview,
      invocation.identity,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) &&
    @json.object_field(context, "effect_source_artifacts") is Some(artifacts) &&
    @json.object_field(artifacts, effect_id) is Some(stored) &&
    evidence_contract_equal(
      stored, artifact, max_wire_bytes, max_nodes, max_depth,
    ) &&
    effect_preview_member_result_artifact_cid(preview, member_index)
    is Some(expected) else {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_capture"))
  }
  admit_captured_effect_source_binding(
    preview, member_index, invocation, artifact, expected, store_authority_cid,
  )
}

///|
/// Project the semantic Result only through the exact captured source/member.
/// This immutable view never restores Compute or grants physical Store custody.
pub fn captured_effect_source_result_from_capture(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  source : CapturedEffectSourceArtifact,
  captured : PublicationContract,
  store_authority_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  guard effect_preview_member_relation_source(preview, member_index)
    is Some(Result(_)) else {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_result"))
  }
  captured_effect_source_relation_artifact_from_capture(
    preview, member_index, invocation, source, captured, store_authority_cid, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
/// Restore the private semantic Artifact only for its exact Table member.
/// This projection is not an ordinary Result and does not restore live custody.
pub fn captured_effect_source_table_input_from_capture(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  source : CapturedEffectSourceArtifact,
  captured : PublicationContract,
  store_authority_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  guard effect_preview_member_relation_source(preview, member_index)
    is Some(TableInput(_)) else {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_table_input"))
  }
  captured_effect_source_relation_artifact_from_capture(
    preview, member_index, invocation, source, captured, store_authority_cid, max_wire_bytes,
    max_nodes, max_depth,
  )
}

///|
fn captured_effect_source_relation_artifact_from_capture(
  preview : EffectPreviewIdentity,
  member_index : Int,
  invocation : PublicationContract,
  source : CapturedEffectSourceArtifact,
  captured : PublicationContract,
  store_authority_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, CapturedRunIssuanceIssue] {
  guard admit_captured_effect_source_from_capture(
      preview,
      member_index,
      invocation,
      source.artifact,
      captured,
      store_authority_cid,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Ok(expected) &&
    expected.effect_id == source.effect_id &&
    expected.holding_cid == source.holding_cid &&
    @json.object_field(captured.value, "effect_context") is Some(context) &&
    @json.object_field(context, "effect_source_local_inventory")
    is Some(inventory) &&
    @json.object_field(inventory, source.effect_id) is Some(local_value) &&
    admitted_nested_local_contract(
      local_value, "artifact", "result_artifact", max_wire_bytes, max_nodes, max_depth,
    )
    is Some(result) else {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_result"))
  }
  Ok(result)
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
