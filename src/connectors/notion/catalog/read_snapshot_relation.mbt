///|
fn read_snapshot_relation_schema(
  snapshot : NotionDatabaseReadSnapshot,
  resource : String,
  limits : NotionReadSnapshotLimits,
) -> Result[(String, String), NotionReadSnapshotIssue] {
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
  Ok((schema_wire, schema_cid))
}

///|
fn emit_snapshot_relation_view(
  writer : @encode.Writer,
  resource : String,
  schema_wire : String,
  schema_cid : String,
) -> Unit raise @encode.EncodeFailure {
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
}

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
  let (schema_wire, schema_cid) = match
    read_snapshot_relation_schema(snapshot, resource, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
    emit_snapshot_relation_view(writer, resource, schema_wire, schema_cid)
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

///|
/// Compose already admitted original snapshots into the same existing view
/// specification. Alias work covers every occurrence and exact UTF16 equality
/// comparison; schema/Contract/encoding work retains its independent limits.
/// This DATA does not admit saved custody, installation membership or keys.
pub fn notion_database_read_snapshots_relation_specification(
  views : Array[(String, NotionDatabaseReadSnapshot)],
  limits : NotionReadSnapshotLimits,
  max_views : Int,
  max_alias_work : Int,
) -> Result[String, NotionReadSnapshotIssue] {
  if !read_snapshot_limits_valid(limits) || max_views < 0 || max_alias_work < 0 {
    return Err(InvalidLimits)
  }
  if views.length() > max_views {
    return Err(BudgetExceeded)
  }
  let mut remaining = max_alias_work
  // Compare only under the admitted alias-work budget, before any schema
  // output. No normalization merges distinct original alias Strings.
  for index in 0..<views.length() {
    let (resource, _) = views[index]
    if resource.length() >= remaining {
      return Err(BudgetExceeded)
    }
    remaining = remaining - resource.length() - 1
    for previous in 0..<index {
      let (other, _) = views[previous]
      if remaining == 0 || resource.length() > remaining - 1 {
        return Err(BudgetExceeded)
      }
      remaining = remaining - resource.length() - 1
      if other.length() > remaining {
        return Err(BudgetExceeded)
      }
      remaining = remaining - other.length()
      if resource == other {
        return Err(InvalidSnapshot)
      }
    }
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
    for (resource, snapshot) in views {
      let (schema_wire, schema_cid) = match
        read_snapshot_relation_schema(snapshot, resource, limits) {
        Ok(value) => value
        Err(issue) => {
          @encode.cancel_writer(writer)
          return Err(issue)
        }
      }
      emit_snapshot_relation_view(writer, resource, schema_wire, schema_cid)
    }
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
