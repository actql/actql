///|
/// Project this same saved full database schema into the existing generic
/// RowRelationViewSpec input. The row-source owner still admits its Catalog
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
        ("schema_cid", snapshot.schema_cid),
        ("schema_wire", snapshot.schema_wire),
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
