///|
pub(all) enum TableStorageMappingIssue {
  InvalidLimits
  UnsupportedColumnCount
  InvalidColumnName(String)
  ColumnCollision(String)
  UnsupportedType(String)
  SavedMapping(TableContractIssue)
  Encoding
} derive(Eq, Debug)

///|
/// Physical encoding of the exact schema established by a completed Relation
/// export. This does not approve publication or establish storage custody.
struct TableStorageMapping {
  cid : String
  schema_cid : String
  wire : String
}

///|
fn emit_table_storage_mapping(
  schema : @schema.Schema,
  schema_cid : String,
  types : Array[String],
  writer : @encode.Writer,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "columns")
  @encode.begin_array(writer)
  let mut field_id = 1
  for i in 0..<types.length() {
    let field = @schema.field_at(schema, i).unwrap()
    let conditional = @schema.field_presence(field) == @schema.Conditional
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, @schema.field_reference_name(field))
    @encode.key(writer, "nullable")
    @encode.bool_value(writer, @contract.contract_nullable(field.contract))
    @encode.key(writer, "physical_type")
    @encode.string_value(writer, types[i])
    @encode.key(writer, "presence")
    @encode.string_value(
      writer,
      if conditional {
        "conditional"
      } else {
        "required"
      },
    )
    @encode.key(writer, "presence_field_id")
    if conditional {
      @encode.number_value(writer, (field_id + 1).to_double())
    } else {
      @encode.null_value(writer)
    }
    @encode.key(writer, "value_field_id")
    @encode.number_value(writer, field_id.to_double())
    @encode.end_object(writer)
    field_id += if conditional { 2 } else { 1 }
  }
  @encode.end_array(writer)
  @encode.key(writer, "iceberg_format_version")
  @encode.number_value(writer, 2.0)
  if self_cid is Some(cid) {
    @encode.key(writer, "mapping_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "schema_cid")
  @encode.string_value(writer, schema_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-table-storage-mapping/0.1")
  @encode.end_object(writer)
}

///|
/// Select physical field IDs from canonical schema order, before any staging.
/// The pinned new-table writer must verify that Catalog assignment preserves
/// these IDs; it must not silently substitute an independently authored map.
/// Actual rows, including an empty export, never narrow the declared schema.
pub fn issue_table_storage_mapping(
  receipt : @execution.CompletedRelationExportReceipt,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[TableStorageMapping, TableStorageMappingIssue] {
  if max_bytes < 1 ||
    max_bytes > 65536 ||
    max_nodes < 1 ||
    max_nodes > 16384 ||
    max_depth < 1 ||
    max_depth > 16 {
    return Err(InvalidLimits)
  }
  let schema = @execution.output_stream_schema(
    @execution.completed_relation_export_content(receipt),
  )
  issue_table_storage_mapping_schema(
    schema,
    @execution.completed_relation_export_schema_identity(receipt),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
fn issue_table_storage_mapping_schema(
  schema : @schema.Schema,
  identity : @execution.RelationSchemaIdentity,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[TableStorageMapping, TableStorageMappingIssue] {
  let count = @schema.field_count(schema)
  if count < 1 || count > 1024 {
    return Err(UnsupportedColumnCount)
  }
  let names : Map[String, Unit] = Map([])
  let types : Array[String] = []
  for i in 0..<count {
    let field = @schema.field_at(schema, i).unwrap()
    let name = @schema.field_reference_name(field)
    if !table_name_valid(name) {
      return Err(InvalidColumnName(name))
    }
    let folded = name.to_lower()
    if folded.has_prefix("__actql_presence_") || names.contains(folded) {
      return Err(ColumnCollision(name))
    }
    names[folded] = ()
    let kind = match field.contract.shape {
      @contract.Boolean => "boolean"
      @contract.Number => "double"
      @contract.Text(_) => "string"
      _ => return Err(UnsupportedType(name))
    }
    types.push(kind)
  }
  let schema_cid = @execution.relation_schema_cid(identity)
  try {
    let hash = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    emit_table_storage_mapping(schema, schema_cid, types, hash, None)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let writer = @encode.writer(max_bytes, max_nodes, max_depth)
    emit_table_storage_mapping(schema, schema_cid, types, writer, Some(cid))
    Ok({ cid, schema_cid, wire: @encode.finish(writer), })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn table_storage_mapping_cid(value : TableStorageMapping) -> String {
  value.cid
}

///|
pub fn table_storage_mapping_schema_cid(value : TableStorageMapping) -> String {
  value.schema_cid
}

///|
pub fn table_storage_mapping_json(value : TableStorageMapping) -> String {
  value.wire
}

///|
/// Re-admit an exact saved physical mapping. The operation and captured Result
/// must separately bind its schema/CID; these bytes do not establish an export,
/// source availability, approval or Catalog authority.
pub fn admit_table_storage_mapping(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[TableStorageMapping, TableStorageMappingIssue] {
  let (value, cid) = match
    table_sealed_value(
      wire,
      "mapping_cid",
      max_bytes,
      max_nodes,
      max_depth,
      max_allowed_nodes=16384,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SavedMapping(issue))
  }
  guard @json.object_field_count(value) == Some(5) &&
    ledger_string(value, "version") == Some("actql-table-storage-mapping/0.1") &&
    ledger_integer(value, "iceberg_format_version", 0L) == Some(2L) &&
    ledger_cid(value, "schema_cid") is Some(schema_cid) &&
    @json.object_field(value, "columns") is Some(@json.Array(columns)) else {
    return Err(SavedMapping(InvalidShape))
  }
  let count = @json.array_count(columns)
  if count < 1 || count > 1024 {
    return Err(UnsupportedColumnCount)
  }
  let names : Map[String, Unit] = Map([])
  let mut previous : String? = None
  let mut field_id = 1L
  for index in 0..<count {
    let column = @json.array_at(columns, index).unwrap()
    guard @json.object_field_count(column) == Some(6) &&
      ledger_string(column, "name") is Some(name) &&
      @json.object_field(column, "nullable") is Some(@json.Bool(_)) &&
      ledger_string(column, "physical_type") is Some(kind) &&
      ledger_string(column, "presence") is Some(presence) &&
      (presence == "required" || presence == "conditional") &&
      ledger_integer(column, "value_field_id", 1L) == Some(field_id) else {
      return Err(SavedMapping(InvalidShape))
    }
    if !table_name_valid(name) {
      return Err(InvalidColumnName(name))
    }
    let folded = name.to_lower()
    if folded.has_prefix("__actql_presence_") || names.contains(folded) {
      return Err(ColumnCollision(name))
    }
    if previous is Some(before) && @canonical.compare_utf16(before, name) >= 0 {
      return Err(SavedMapping(InvalidShape))
    }
    if kind != "boolean" && kind != "double" && kind != "string" {
      return Err(UnsupportedType(name))
    }
    if presence == "conditional" {
      if ledger_integer(column, "presence_field_id", 1L) != Some(field_id + 1L) {
        return Err(SavedMapping(InvalidShape))
      }
      field_id += 2L
    } else {
      guard @json.object_field(column, "presence_field_id") is Some(@json.Null) else {
        return Err(SavedMapping(InvalidShape))
      }
      field_id += 1L
    }
    names[folded] = ()
    previous = Some(name)
  }
  Ok({ cid, schema_cid, wire, })
}

///|
/// Content-level correspondence only; the Host issuer separately checks the
/// exact captured owners, approved target and current authority.
pub fn table_operation_matches_input(
  value : TableOperation,
  scope : @request_scope.LogicalRequestScope,
  effect_cid : String,
  artifact_cid : String,
  relation_cid : String,
  mapping : TableStorageMapping,
  data_policy_cid : String,
) -> Bool {
  value.scope_cid == @request_scope.logical_request_scope_cid(scope) &&
  value.effect_cid == effect_cid &&
  value.input_artifact_cid == artifact_cid &&
  value.input_relation_cid == relation_cid &&
  value.schema_cid == mapping.schema_cid &&
  value.mapping_cid == mapping.cid &&
  value.data_policy_cid == data_policy_cid
}

///|
pub fn table_operation_cid(value : TableOperation) -> String {
  value.cid
}

///|
pub fn table_operation_json(value : TableOperation) -> String {
  value.wire
}
