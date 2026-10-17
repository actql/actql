///|
/// Project this same saved full database schema's checked fields into the
/// existing RowRelationViewSpec input. Its field-map identity is distinct from
/// the saved complete Object contract. The row-source owner admits its Catalog
/// and contracts. This does not assert keys, acquisition facts, a Reference,
/// installation membership, current authority or a funded physical reader.
pub fn notion_database_read_snapshot_relation_specification(
  snapshot : NotionDatabaseReadSnapshot,
  resource : String,
  limits : NotionReadSnapshotLimits,
) -> Result[String, NotionReadSnapshotIssue] {
  if !read_snapshot_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  if !read_snapshot_is_original(snapshot) {
    return Err(ForeignOriginal)
  }
  // User-authored property names cannot establish the fixed system binding.
  if snapshot.read_contracts.system_columns.length() != 8 {
    return Err(SchemaMismatch)
  }
  if resource.is_empty() {
    return Err(InvalidSnapshot)
  }
  if resource.length() > limits.max_bytes {
    return Err(BudgetExceeded)
  }
  if @admitted.text_value(resource, limits.max_bytes) is None {
    return Err(InvalidSnapshot)
  }
  guard snapshot.read_contracts.schema.shape is @contract.Object(fields) &&
    !snapshot.read_contracts.schema.nullable else {
    return Err(SchemaMismatch)
  }
  // The existing Relation owner consumes a field-contract map, rather than
  // the complete Object contract saved by the snapshot. Emit the same checked
  // child contracts with their original order, constraints and nullability.
  let schema_writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  let schema_wire = try {
    @encode.begin_ordered_object(schema_writer)
    for index in 0..<@contract.field_count(fields) {
      let field = @contract.field_at(fields, index).unwrap()
      @encode.ordered_key(schema_writer, field.name)
      @contract.emit_checked(field.contract, schema_writer)
    }
    @encode.end_object(schema_writer)
    @encode.finish(schema_writer)
  } catch {
    _ => {
      @encode.cancel_writer(schema_writer)
      return Err(BudgetExceeded)
    }
  }
  let schema_cid = "sha256:" + @sha.hex(@utf8.encode(schema_wire))
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "views")
    @encode.begin_array(writer)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("resource", resource),
        ("resource_kind", "notion_database"),
        ("schema_cid", schema_cid),
        ("schema_wire", schema_wire),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}
