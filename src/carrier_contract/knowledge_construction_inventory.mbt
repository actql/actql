///|
/// The original typed_rows/rows wrapper copies field records and retains its
/// supplied Schema. This does not re-read child value contracts or create rows.
pub(all) struct KnowledgeConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn typed_rows_construction_inventory(
  fields : Int,
) -> KnowledgeConstructionInventory? {
  if fields < 0 {
    return None
  }
  let f = fields.to_int64()
  Some({
    retained: typed_rows_retained_extent(fields, 1).unwrap(),
    scratch: @shape.collection_construction_extent({
      records: 4L + 2L * f,
      record_references: 4L + 3L * f,
      record_words: 2L + f,
      reference_arrays: 1L,
      reference_items: f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    }).unwrap(),
    scratch_utf16_units: 0L,
  })
}

///|
/// Actual unqualified all-typed fields supplied by the Graph reader. The
/// ordinary row constructor still validates its original names and limits.
pub fn unqualified_rows_construction_inventory(
  fields : Int,
  max_name_utf16_units : Int,
) -> KnowledgeConstructionInventory? {
  guard @row.unqualified_presence_construction_inventory(
      fields, max_name_utf16_units,
    )
    is Some(schema) &&
    typed_rows_construction_inventory(fields) is Some(typed) else {
    return None
  }
  let f = fields.to_int64()
  // Original placeholder, input mapping and types Map; admitted fields and
  // returned Knowledge coexist with the original Schema, not child copies.
  let input = @shape.collection_construction_extent({
    records: 5L + 2L * f,
    record_references: 4L + 4L * f,
    record_words: 5L + f,
    reference_arrays: 2L,
    reference_items: 2L * f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: f,
  }).unwrap()
  Some({
    retained: unqualified_rows_retained_extent(fields, 1).unwrap(),
    scratch: @shape.add_collection_construction_extents(
      input,
      @shape.add_collection_construction_extents(schema.scratch, typed.scratch).unwrap(),
    ).unwrap(),
    scratch_utf16_units: schema.scratch_utf16_units,
  })
}

///|
pub fn typed_rows_retained_extent(
  fields : Int,
  instances : Int,
) -> @shape.CollectionConstructionExtent? {
  if fields < 0 || instances < 0 {
    return None
  }
  let f = fields.to_int64()
  let i = instances.to_int64()
  @shape.collection_construction_extent({
    records: 2L * i + 3L * f,
    record_references: 3L * i + 4L * f,
    record_words: 3L * i + f,
    reference_arrays: i,
    reference_items: f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}

///|
pub fn unqualified_rows_retained_extent(
  fields : Int,
  instances : Int,
) -> @shape.CollectionConstructionExtent? {
  guard @row.unqualified_presence_retained_extent(fields, instances)
    is Some(schema) &&
    typed_rows_retained_extent(fields, instances) is Some(typed) else {
    return None
  }
  @shape.add_collection_construction_extents(schema, typed)
}
