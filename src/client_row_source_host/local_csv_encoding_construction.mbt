///|
fn local_csv_encoding_wire_bounds(
  width : Int,
  field_text_units : Int64,
  key_count : Int,
  key_text_units : Int64,
) -> (Int, Int)? {
  if !local_csv_column_count_is_valid(width) ||
    key_count < 0 ||
    key_count > width {
    return None
  }
  // The longer scalar spelling is string. Include quotes, colon and a
  // separator for each field, with the last separator replaced by a brace.
  let field = "\"\":{\"nullable\":false,\"type\":\"string\"},"
    .length()
    .to_int64()
  guard @execution.checked_preparation_add_product(
      1L + width.to_int64() * field,
      field_text_units,
      6L,
    )
    is Some(schema) else {
    return None
  }
  let facts = if key_count == 0 {
    2L
  } else {
    let fixed = "{\"relation_keys\":{\"candidate_keys\":[[]]}}"
      .length()
      .to_int64()
    guard @execution.checked_preparation_add_product(
        fixed + 3L * key_count.to_int64(),
        key_text_units,
        6L,
      )
      is Some(facts) else {
      return None
    }
    facts
  }
  let limit = relation_restore_limits.max_bytes.to_int64()
  Some((Int64::min(schema, limit).to_int(), Int64::min(facts, limit).to_int()))
}

///|
fn local_csv_table_assembly_inventory(
  width : Int,
  key_count : Int,
) -> @execution.PreparationRepresentationUnits? {
  let w = width.to_int64()
  let k = key_count.to_int64()
  let keyed = if key_count > 0 { 1L } else { 0L }
  guard @shape.collection_construction_extent({
      // Fixed returned Table/View and Result/Option controls, original field
      // cursors, literal facts containers and scalar validation results.
      // Per column: field_at/Cursor/text controls and typed Json (three
      // variants, two literal pairs). Per key: element_at + lookup/Cursor/text
      // controls plus the retained Json string. Original text is borrowed.
      records: 32L + w * (6L + 5L) + k * (9L + 1L),
      record_references: 56L + w * (9L + 6L) + k * (14L + 1L),
      record_words: 40L + w * (6L + 3L) + k * (8L + 1L),
      // Column names and key Array, one literal pair Array for each column
      // schema, then the mapped key Array, candidate list and two facts pairs.
      reference_arrays: 2L + w + 4L * keyed,
      reference_items: 3L * w + k + keyed * (k + 3L),
      scalar_arrays: 1L,
      scalar_items: w,
      // Schema and per-column Maps, checked-key membership Map, facts Map(s).
      // The decoder's original column-name index is a separate constructor.
      maps: 3L + w + keyed,
      map_entries: 3L * w + k + 2L * keyed,
    })
    is Some(assembly) else {
    return None
  }
  let units = relation_construction_collection_units(assembly)
  if key_count == 0 {
    return Some(units)
  }
  guard @decode.open_object_construction_extent(width) is Some(columns) else {
    return None
  }
  @execution.compose_preparation_representation([
    units,
    relation_construction_collection_units(columns),
  ])
}

///|
/// Bounded column and key geometry shared by typed and transport projections.
pub(all) struct LocalCsvTableMetadataGeometry {
  width : Int
  key_count : Int
  field_text_units : Int64
  key_text_units : Int64
  schema_bytes : Int
  facts_bytes : Int
}

///|
/// Borrow field/key lengths without constructing a detached array or a view.
/// The caller retains the selected CSV classifier and original table cursor.
pub fn local_csv_table_metadata_geometry(
  table : @decode.Cursor,
) -> LocalCsvTableMetadataGeometry? {
  guard @decode.lookup_original_field(table, "columns") is Some(columns) &&
    @decode.object_length(columns) is Some(width) &&
    local_csv_column_count_is_valid(width) else {
    return None
  }
  let mut field_text_units = 0L
  for index in 0..<width {
    guard @decode.field_at(columns, index) is Some((name, _)) else {
      return None
    }
    field_text_units += name.length().to_int64()
  }
  let (key_count, key_text_units) = match
    @decode.lookup_original_field(table, "key") {
    None => (0, 0L)
    Some(keys) =>
      match @decode.array_length(keys) {
        Some(count) if count > 0 && count <= width => {
          let mut units = 0L
          for index in 0..<count {
            if @decode.element_at(keys, index) is Some(key) &&
              @decode.is_text(key) &&
              @decode.text(key) is Ok(name) {
              units += name.length().to_int64()
            }
          }
          (count, units)
        }
        // A malformed container refuses after the column arrays and before
        // the column-name index. It does not change the typed refusal.
        _ => (0, 0L)
      }
  }
  guard local_csv_encoding_wire_bounds(
      width, field_text_units, key_count, key_text_units,
    )
    is Some((schema_bytes, facts_bytes)) else {
    return None
  }
  Some({
    width,
    key_count,
    field_text_units,
    key_text_units,
    schema_bytes,
    facts_bytes,
  })
}

///|
/// The selected table's typed projection after the bounded original census.
/// Census, final Project vector and Node transport have separate owners.
pub fn local_csv_table_construction_inventory(
  table : @decode.Cursor,
) -> @execution.PreparationRepresentationUnits? {
  guard local_csv_table_is_selected(table) else { return None }
  guard local_csv_table_metadata_geometry(table) is Some(geometry) else {
    // The existing constructor refuses before allocating a column array.
    // Its original typed refusal still belongs to that constructor.
    return local_csv_table_assembly_inventory(0, 0)
  }
  let width = geometry.width
  let key_count = geometry.key_count
  // Bound the root, column objects, their fields and scalar wrappers. The
  // facts object owns one candidate-key list, not a Cartesian key expansion.
  let schema_nodes = 1 + 5 * width
  let facts_nodes = if key_count == 0 { 1 } else { 5 + key_count }
  let facts_depth = if key_count == 0 { 1 } else { 4 }
  guard local_csv_table_assembly_inventory(width, key_count) is Some(assembly) &&
    relation_public_projection_canonical(schema_nodes, 3 * schema_nodes, 1L)
    is Some(schema_tree) &&
    relation_public_projection_canonical(
      facts_nodes,
      (facts_depth + 1) * facts_nodes,
      1L,
    )
    is Some(facts_tree) &&
    relation_construction_writer_units(geometry.schema_bytes, schema_nodes, 2)
    is Some(schema_writer) &&
    relation_construction_writer_units(
      geometry.facts_bytes,
      facts_nodes,
      facts_depth,
    )
    is Some(facts_writer) &&
    relation_projection_schema_hash_inventory(
      1L,
      geometry.schema_bytes.to_int64(),
    )
    is Some(schema_hash) else {
    return None
  }
  @execution.compose_preparation_representation([
    assembly, schema_tree, facts_tree, schema_writer, facts_writer, schema_hash,
  ])
}
