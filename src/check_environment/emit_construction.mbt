///|
// SAME emit_except pending stack and indexed Cursor/field helpers, independent
// of its output sink. Input tree/key Strings are borrowed. Pending node count
// comes from the original emission geometry, never a configured limit.
fn wire_traversal_construction_extent(
  pending_nodes : Int,
) -> @shape.CollectionConstructionExtent {
  let n = pending_nodes.to_int64()
  let child = @decode.indexed_child_construction_extent()
  let field = @decode.indexed_field_construction_extent()
  // ObjectNext/previous-Some/Cursor3H5R4W per pending node. Fixed helpers
  // include the popped frame. Returned CID Strings belong only to hash calls.
  @shape.collection_construction_extent({
    records: 4L + field.record_headers + child.record_headers + 3L * n,
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
}

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
  let traversal = wire_traversal_construction_extent(nodes)
  let hash = @encode.hash_writer_construction_inventory(nodes, nodes).unwrap()
  Some({
    record_headers: traversal.record_headers + hash.record_headers + 2L,
    reference_slots: traversal.reference_slots + hash.reference_slots,
    scalar_words: traversal.scalar_words + hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + 142L,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
/// SAME member serializer and unbuffered writer, through returned text only.
/// A pending stack has one parent frame per open container plus its next Visit;
/// actual node count also bounds it. No CID/hash/UTF8/parser/schema is included.
pub fn wire_text_construction_extent(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> RegistryConstructionExtent? {
  guard @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(text) else {
    return None
  }
  let pending = Int64::min(nodes.to_int64(), depth.to_int64() + 1L).to_int()
  let traversal = wire_traversal_construction_extent(pending)
  Some({
    record_headers: traversal.record_headers + text.record_headers,
    reference_slots: traversal.reference_slots + text.reference_slots,
    scalar_words: traversal.scalar_words + text.scalar_words,
    owned_utf16_units: text.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
/// Bind emission inventory to this SAME admitted Member's retained metrics.
/// This does not walk/hash/parse its body or admit it as a Local Snapshot.
pub fn member_text_emission_construction_extent(
  original_member : Member,
) -> RegistryConstructionExtent {
  let (bytes, nodes, depth) = member_emission_geometry(original_member)
  wire_text_construction_extent(bytes, nodes, depth).unwrap()
}
