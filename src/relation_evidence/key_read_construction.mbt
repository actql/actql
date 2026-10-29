///|
/// Original local primary-key reader storage. This DATA neither proves a key
/// nor changes uniqueness, comparability, field-name or source obligations.
/// Returned String/Contract/Knowledge/source bodies stay borrowed originals.
pub(all) struct KeyReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
/// Actual selected array width and name length, not max_fields or another
/// input's schema. One key name is validated at a time by the existing Object
/// name owner; no normalization table, new tariff or authority is introduced.
pub fn primary_key_read_construction_inventory(
  fields : Int,
  max_name_utf16_units : Int,
  root_path_depth : Int64,
) -> KeyReadConstructionInventory? {
  if fields < 0 ||
    max_name_utf16_units < 0 ||
    root_path_depth < 0L ||
    root_path_depth == 9223372036854775807L {
    return None
  }
  let n = fields.to_int64()
  guard @contract.object_construction_inventory(1, max_name_utf16_units)
    is Some(name) &&
    @decode.issue_path_construction_extent(root_path_depth + 1L) is Some(path) else {
    return None
  }
  // KeyedRelation1H8R1W, Usage1H2W; each original KeyField1H3R and
  // Unqualified name1H1R1W. declared_fields and fields are SAME Array.
  // Outer aliases and each singleton alias keep references to SAME KeyField.
  let retained = @shape.collection_construction_extent({
    records: 2L + 2L * n,
    record_references: 8L + 4L * n,
    record_words: 3L + n,
    reference_arrays: 2L + n,
    reference_items: 3L * n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let utf8 = @scalar.utf8_length_admission_construction_units()
  // elements owns one Cursor per item; seen is original duplicate detection.
  // The one-slot name-check Array/tuple/primitive and transient Result/Some/
  // lookup/Issue/Stop alternatives18H16R20W coexist with that input inventory.
  // The name owner's admitted temporary Object is discarded before next key.
  let frame = @shape.collection_construction_extent({
    records: n + 18L + utf8.0,
    record_references: 2L * n + 16L + utf8.1,
    record_words: n + 20L + utf8.2,
    reference_arrays: 2L,
    reference_items: n + 1L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: n,
  }).unwrap()
  // A decoded child failure copies its original diagnostic path into this
  // existing key Issue, so both paths can coexist. Span/text bodies are shared.
  let scratch = @shape.add_collection_construction_extents(
    frame,
    @shape.add_collection_construction_extents(
      name.retained,
      @shape.add_collection_construction_extents(
        name.scratch,
        @shape.add_collection_construction_extents(path, path).unwrap(),
      ).unwrap(),
    ).unwrap(),
  ).unwrap()
  Some({ retained, scratch, scratch_utf16_units: name.scratch_utf16_units, })
}
