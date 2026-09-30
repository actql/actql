///|
/// Project retained publication evidence without opening the payload generation.
/// The environment must authorize the request and confirm the committed index.
pub fn describe_committed_result(
  index : PublicationContract,
  manifest : PublicationContract,
  result_name : String,
  bindings : Array[PublicationContract],
  definition : PublicationContract,
  schema_wire : String,
  format : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, DeliveryIssuanceIssue] {
  let selected = match
    project_committed_result_read(index, manifest, result_name, bindings) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if definition.name != "result_definition" ||
    definition.identity != selected.result_definition_cid ||
    contract_string(definition, "result_name") != Some(result_name) {
    return Err(DeliveryIssuanceReferenceMismatch("description.definition"))
  }
  match
    validate_result_schema_wire(
      selected.result_schema_cid,
      schema_wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let schema = match
    parse_contract_wire(schema_wire, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(_) => return Err(DeliveryIssuanceEncoding)
  }
  // Reuse the delivery owner's field and format admission. No serializer is
  // started, and no delivery attempt or payload read is created here.
  match
    prepare_result_delivery_serializer(
      format,
      schema_wire,
      selected.result_fields,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(_) =>
      return Err(DeliveryIssuanceReferenceMismatch("description.delivery"))
  }
  let serialization_cid = match
    result_serialization_contract_cid(
      format, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(DeliveryIssuanceEncoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "columns")
    @encode.begin_array(writer)
    for field in selected.result_fields {
      guard @json.object_field(schema, field) is Some(contract) else {
        return Err(DeliveryIssuanceReferenceMismatch("description.columns"))
      }
      @encode.begin_object(writer)
      @encode.key(writer, "contract")
      @json.emit_value(contract, writer)
      @encode.key(writer, "name")
      @encode.string_value(writer, field)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "programDefinitionCid")
    @encode.string_value(
      writer,
      contract_string(definition, "program_definition_cid").unwrap(),
    )
    @encode.key(writer, "resultArtifactCid")
    @encode.string_value(writer, selected.result_artifact_cid)
    @encode.key(writer, "resultDefinitionCid")
    @encode.string_value(writer, selected.result_definition_cid)
    @encode.key(writer, "resultName")
    @encode.string_value(writer, result_name)
    @encode.key(writer, "resultSchemaCid")
    @encode.string_value(writer, selected.result_schema_cid)
    @encode.key(writer, "serialization")
    @encode.begin_object(writer)
    @encode.key(writer, "contractCid")
    @encode.string_value(writer, serialization_cid)
    @encode.key(writer, "format")
    @encode.string_value(writer, format)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-" + format + "/0.1")
    @encode.end_object(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(DeliveryIssuanceEncoding)
  }
}
