///|
pub(all) enum TableStorageMappingIssue {
  InvalidLimits
  UnsupportedColumnCount
  InvalidColumnName(String)
  ColumnCollision(String)
  UnsupportedType(String)
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
