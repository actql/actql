///|
/// SAME canonical emit_except pending stack and existing hashing writer.
/// Input strings/tree are borrowed. Returned CID strings can coexist with one
/// writer; caller-retained full hashes have their own inventory. Not a tariff.
pub fn wire_hash_construction_extent(
  nodes : Int,
) -> RegistryConstructionExtent? {
  if nodes < 1 {
    return None
  }
  let n = nodes.to_int64()
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // ObjectNext/previous-Some/Cursor3H5R4W per pending node. Indexed field,
  // element, length and view helpers12H12R6W plus popped-frame Some1H1R.
  // Two returned CID String71 records, one pending Array. No node/depth policy
  // ceiling is used as demand; actual admitted node count bounds both.
  let collection = @shape.collection_construction_extent({
    records: 6L + field.record_headers + child.record_headers + 3L * n,
    record_references: 2L +
    field.reference_slots +
    child.reference_slots +
    5L * n,
    record_words: 3L + field.scalar_words + child.scalar_words + 4L * n,
    reference_arrays: 1L,
    reference_items: n,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let hash = @encode.hash_writer_construction_inventory(nodes, nodes).unwrap()
  Some({
    record_headers: collection.record_headers + hash.record_headers,
    reference_slots: collection.reference_slots + hash.reference_slots,
    scalar_words: collection.scalar_words + hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + 142L,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}
