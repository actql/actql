///|
/// A SQL/schema candidate within one original metadata observation. No grant,
/// Acquisition receipt or provider statement outcome is constructed here.
pub struct ReadProjection {
  priv description : TableDescription
  priv fields : Array[String]
  priv statement : String
  priv schema_wire : String
  priv schema_cid : String
}

///|
fn quote_identifier(value : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for character in value.iter() {
    if character == '"' {
      out.write_char('"')
    }
    out.write_char(character)
  }
  out.write_char('"')
  out.to_string()
}

///|
pub fn prepare_read_projection(
  description : TableDescription,
  selected : Array[String],
  limits : DescriptionLimits,
) -> Result[ReadProjection, DescriptionIssue] {
  if !valid_description_limits(limits) {
    return Err(InvalidLimits)
  }
  if selected.is_empty() ||
    selected.length() > limits.max_columns ||
    description.columns.length() > limits.max_columns {
    return Err(InvalidSelection)
  }
  let mut name_bytes = limits.max_name_bytes
  for
    name in [
      description.target.database,
      description.target.schema,
      description.target.table,
    ] {
    match @scalar.admit_utf8_length(name, name_bytes) {
      Ok(size) => name_bytes -= size
      Err(_) => return Err(DescriptionLimit)
    }
  }
  for column in description.columns {
    for name in [column.name, column.native_type] {
      match @scalar.admit_utf8_length(name, name_bytes) {
        Ok(size) => name_bytes -= size
        Err(_) => return Err(DescriptionLimit)
      }
    }
  }
  let fields : Array[(String, @contract.Contract)] = []
  let names = []
  for name in selected {
    if names.contains(name) {
      return Err(DuplicateColumn(name))
    }
    let mut found = None
    for column in description.columns {
      if column.name == name {
        found = Some(column)
        break
      }
    }
    guard found is Some(column) else { return Err(UnknownColumn(name)) }
    guard column.contract is Some(contract) else {
      return Err(UnsupportedType(name, column.native_type))
    }
    fields.push((name, contract))
    names.push(name)
  }
  // Common validates exact field names and canonical UTF-16 order. No
  // identifier normalization or hand-written schema comparator is used.
  let object = match
    @contract.object_contract(
      fields,
      nullable=false,
      max_fields=limits.max_columns,
      max_name_bytes=limits.max_name_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidSchema)
  }
  guard object.shape is @contract.Object(ordered) else {
    return Err(InvalidSchema)
  }
  try {
    let schema = @encode.writer(
      limits.max_schema_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_ordered_object(schema)
    for index in 0..<@contract.field_count(ordered) {
      let field = @contract.field_at(ordered, index).unwrap()
      @encode.ordered_key(schema, field.name)
      @contract.emit_checked(field.contract, schema)
    }
    @encode.end_object(schema)
    let schema_wire = @encode.finish(schema)
    // This is exact UTF-8 schema output; quoted physical names below retain
    // the provider's original spelling and never become unquoted SQL syntax.
    let target = description.target
    // Admit every byte and doubled quote before building SQL output. This is
    // a bounded physical spelling, not parsing or accepting caller SQL.
    let mut sql_bytes = limits.max_schema_bytes
    if sql_bytes < 15 || names.length() - 1 > sql_bytes - 15 {
      return Err(DescriptionLimit)
    }
    sql_bytes -= 15 + names.length() - 1
    for identifier in [..names, target.database, target.schema, target.table] {
      if sql_bytes < 2 {
        return Err(DescriptionLimit)
      }
      sql_bytes -= 2
      match @scalar.admit_utf8_length(identifier, sql_bytes) {
        Ok(size) => sql_bytes -= size
        Err(_) => return Err(DescriptionLimit)
      }
      for character in identifier.iter() {
        if character == '"' {
          if sql_bytes == 0 {
            return Err(DescriptionLimit)
          }
          sql_bytes -= 1
        }
      }
    }
    let statement = "SELECT " +
      names.map(quote_identifier).join(",") +
      " FROM " +
      quote_identifier(target.database) +
      "." +
      quote_identifier(target.schema) +
      "." +
      quote_identifier(target.table)
    if @scalar.admit_utf8_length(statement, limits.max_schema_bytes) is Err(_) {
      return Err(DescriptionLimit)
    }
    Ok({
      description,
      fields: names,
      statement,
      schema_wire,
      schema_cid: "sha256:" + @sha.hex(@utf8.encode(schema_wire)),
    })
  } catch {
    _ => Err(DescriptionLimit)
  }
}

///|
pub fn read_projection_matches_description(
  projection : ReadProjection,
  description : TableDescription,
) -> Bool {
  physical_equal(projection.description, description)
}

///|
pub fn read_projection_statement(projection : ReadProjection) -> String {
  projection.statement
}

///|
pub fn read_projection_fields(projection : ReadProjection) -> Array[String] {
  projection.fields.copy()
}

///|
pub fn read_projection_schema(projection : ReadProjection) -> (String, String) {
  (projection.schema_wire, projection.schema_cid)
}

///|
/// The existing Common declaration Owner validates this schema again and
/// issues its Catalog/SourceView bytes. This data view is not publication.
pub fn read_projection_relation_view(
  projection : ReadProjection,
  resource : String,
) -> @rows.RowRelationViewSpec {
  {
    resource,
    resource_kind: "relation",
    schema_wire: projection.schema_wire,
    schema_cid: projection.schema_cid,
    request_schema_wire: None,
    facts_wire: None,
    acquisition_wire: None,
  }
}

///|
/// Generate only through the existing Common Owner. Calling this does not
/// adopt an installation, authorize a read, refresh metadata or start a Run.
pub fn generate_read_declaration(
  projection : ReadProjection,
  resource : String,
  connector_id : String,
  connector_revision : String,
  limits : @rows.RowDeclarationLimits,
) -> Result[@rows.RowDeclaration, @rows.RowHostIssue] {
  @rows.generate_relation_row_declaration(
    connector_id,
    "snowflake",
    connector_revision,
    [read_projection_relation_view(projection, resource)],
    limits,
  )
}
