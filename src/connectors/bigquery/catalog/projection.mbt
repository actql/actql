///|
/// A selected, Common-admitted schema bound to the same metadata observation.
/// This is not a Job, SQL text, Source receipt, credential or write permission.
pub struct ReadProjection {
  priv original : TableDescription
  priv fields : Array[String]
  priv schema_wire : String
  priv schema_cid : String
}

///|
pub fn prepare_read_projection(
  original : TableDescription,
  selected : Array[String],
  limits : DescriptionLimits,
) -> Result[ReadProjection, DescriptionIssue] {
  if !valid_limits(limits) { return Err(InvalidLimits) }
  if selected.is_empty() || selected.length() > limits.max_fields {
    return Err(InvalidSelection)
  }
  let names : Array[String] = []
  let contracts : Array[(String, @contract.Contract)] = []
  for name in selected {
    if names.contains(name) { return Err(DuplicateColumn(name)) }
    let mut found = None
    for column in original.columns {
      if column.name == name { found = Some(column); break }
    }
    guard found is Some(column) else {
      return Err(UnknownColumn(name))
    }
    guard column.contract is Some(contract) else {
      return Err(UnsupportedColumn(name, column.native_type))
    }
    names.push(name)
    contracts.push((name, contract))
  }
  let root = match @contract.object_contract(contracts, nullable=false,
      max_fields=limits.max_fields, max_name_bytes=limits.max_name_bytes) {
    Ok(value) => value
    Err(_) => return Err(InvalidContract(""))
  }
  guard root.shape is @contract.Object(fields) else { return Err(InvalidContract("")) }
  try {
    let writer = @encode.writer(limits.max_schema_bytes, limits.max_nodes, limits.max_depth)
    @encode.begin_ordered_object(writer)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      @encode.ordered_key(writer, field.name)
      @contract.emit_checked(field.contract, writer)
    }
    @encode.end_object(writer)
    let schema_wire = @encode.finish(writer)
    Ok({original, fields: names, schema_wire,
      schema_cid: "sha256:" + @sha.hex(@utf8.encode(schema_wire))})
  } catch { _ => Err(DescriptionLimit) }
}

///|
pub fn read_projection_matches_description(value : ReadProjection, original : TableDescription) -> Bool {
  physical_equal(value.original, original)
}

///|
pub fn read_projection_fields(value : ReadProjection) -> Array[String] { value.fields.copy() }

///|
pub fn read_projection_schema(value : ReadProjection) -> (String, String) { (value.schema_wire, value.schema_cid) }

///|
/// The existing Common declaration issuer validates and emits Catalog/Source
/// evidence. Unenforced provider key declarations never become uniqueness facts.
pub fn generate_read_declaration(
  value : ReadProjection,
  resource : String,
  connector_id : String,
  connector_revision : String,
  limits : @rows.RowDeclarationLimits,
) -> Result[@rows.RowDeclaration, @rows.RowHostIssue] {
  @rows.generate_relation_row_declaration(connector_id, "bigquery", connector_revision,
    [{resource, resource_kind: "relation", schema_wire: value.schema_wire,
      schema_cid: value.schema_cid, request_schema_wire: None,
      facts_wire: None, acquisition_wire: None}], limits)
}
