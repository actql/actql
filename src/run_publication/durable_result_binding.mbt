///|
pub(all) enum DurableResultBindingIssue {
  DurableBindingWrongContract(String)
  DurableBindingReferenceMismatch(String)
  DurableBindingInvalidPhysicalIdentity
  DurableBindingEncoding
  DurableBindingContract(PublicationContractIssue)
} derive(Eq, Debug)

///|
/// Issue the durable representation binding for one exact admitted Result.
/// The Store adapter supplies only observed physical facts. This portable
/// owner validates every semantic reference and creates the canonical body.
pub fn issue_durable_result_binding(
  run_definition : PublicationContract,
  definition : PublicationContract,
  invocation : PublicationContract,
  artifact : PublicationContract,
  ordering : PublicationContract,
  retention : PublicationContract,
  codec_contract_cid : String,
  result_fields : Array[String],
  result_schema_wire : String,
  material_generation_cid : String,
  store_authority_cid : String,
  row_count : Int,
  byte_count : Int,
  physical_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, DurableResultBindingIssue] {
  for
    (contract, expected) in [
      (run_definition, "run_definition"),
      (definition, "result_definition"),
      (invocation, "run_invocation"),
      (artifact, "result_artifact"),
      (ordering, "ordering_evidence"),
      (retention, "result_retention_policy"),
    ] {
    if contract.name != expected {
      return Err(DurableBindingWrongContract(expected))
    }
  }
  for
    (actual, expected, field) in [
      (
        contract_string(artifact, "result_definition_cid"),
        definition.identity,
        "result_definition_cid",
      ),
      (
        contract_string(artifact, "invocation_cid"),
        invocation.identity,
        "invocation_cid",
      ),
      (
        contract_string(artifact, "ordering_evidence_cid"),
        ordering.identity,
        "ordering_evidence_cid",
      ),
      (
        contract_string(artifact, "effective_retention_policy_cid"),
        retention.identity,
        "effective_retention_policy_cid",
      ),
      (
        contract_string(ordering, "producer_contract_cid"),
        definition.identity,
        "ordering.producer_contract_cid",
      ),
    ] {
    if actual != Some(expected) {
      return Err(DurableBindingReferenceMismatch(field))
    }
  }
  guard contract_string(artifact, "logical_result_cid") is Some(logical_cid) &&
    contract_string(artifact, "result_schema_cid") is Some(schema_cid) else {
    return Err(DurableBindingReferenceMismatch("artifact_identity"))
  }
  if contract_count(artifact, "actual_row_count") != Some(row_count.to_int64()) {
    return Err(DurableBindingReferenceMismatch("row_count"))
  }
  if !valid_contract_cid(codec_contract_cid) ||
    result_fields.is_empty() ||
    !valid_contract_cid(material_generation_cid) ||
    !valid_contract_cid(store_authority_cid) ||
    row_count < 0 ||
    byte_count < 0 ||
    !valid_digest(physical_sha256) {
    return Err(DurableBindingInvalidPhysicalIdentity)
  }
  let seen : Array[String] = []
  for field in result_fields {
    guard @canonical.normalize_nfc_lf(field) is Ok(normalized) else {
      return Err(DurableBindingInvalidPhysicalIdentity)
    }
    if field.is_empty() || normalized != field || seen.contains(field) {
      return Err(DurableBindingInvalidPhysicalIdentity)
    }
    seen.push(field)
  }
  let schema = match
    parse_contract_wire(
      result_schema_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(DurableBindingInvalidPhysicalIdentity)
  }
  guard object_fields(schema) is Ok(schema_fields) else {
    return Err(DurableBindingInvalidPhysicalIdentity)
  }
  let canonical_schema = @json.stringify_value(
    schema, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(DurableBindingEncoding)
  }
  let schema_identity = @json.cid_value(
    schema, max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(DurableBindingEncoding)
  }
  if canonical_schema != result_schema_wire ||
    schema_identity != schema_cid ||
    schema_fields.length() != result_fields.length() ||
    result_fields.any(field => @json.object_field(schema, field) is None) {
    return Err(DurableBindingInvalidPhysicalIdentity)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DurableBindingEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "byte_count")
    @encode.number_value(writer, byte_count.to_double())
    @encode.key(writer, "codec_contract_cid")
    @encode.string_value(writer, codec_contract_cid)
    @encode.key(writer, "effective_retention_policy_cid")
    @encode.string_value(writer, retention.identity)
    @encode.key(writer, "invocation_cid")
    @encode.string_value(writer, invocation.identity)
    @encode.key(writer, "logical_result_cid")
    @encode.string_value(writer, logical_cid)
    @encode.key(writer, "material_generation_cid")
    @encode.string_value(writer, material_generation_cid)
    @encode.key(writer, "ordering_evidence_cid")
    @encode.string_value(writer, ordering.identity)
    @encode.key(writer, "physical_sha256")
    @encode.string_value(writer, physical_sha256)
    @encode.key(writer, "result_fields")
    @encode.begin_array(writer)
    for field in result_fields {
      @encode.string_value(writer, field)
    }
    @encode.end_array(writer)
    @encode.key(writer, "result_definition_cid")
    @encode.string_value(writer, definition.identity)
    @encode.key(writer, "result_schema_cid")
    @encode.string_value(writer, schema_cid)
    @encode.key(writer, "row_count")
    @encode.number_value(writer, row_count.to_double())
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition.identity)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-durable-result-binding/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(DurableBindingEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(DurableBindingEncoding)
  }
  match
    seal_publication_contract(
      "durable_result_binding", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(DurableBindingContract(issue))
  }
}
