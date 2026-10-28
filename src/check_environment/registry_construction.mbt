///|
/// Measurements of original admitted members; no body walk, parse/hash, issuer
/// or registry admission. max_nodes also bounds actual emitter stack/key depth.
pub(all) struct RegistryConstructionGeometry {
  members : Int
  max_nodes : Int
  max_fields : Int
} derive(Eq, Debug)

///|
pub fn observe_registry_construction_geometry(
  environment : WireEnvironment,
) -> RegistryConstructionGeometry {
  let count = member_count(environment, ContractRegistry)
  let mut nodes = 0
  let mut fields = 0
  for index in 0..<count {
    let entry = environment.sections[position(ContractRegistry)][index]
    nodes = Int::max(nodes, entry.nodes)
    fields = Int::max(fields, @decode.object_length(entry.cursor).unwrap())
  }
  { members: count, max_nodes: nodes, max_fields: fields, }
}

///|
pub(all) struct RegistryConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
/// Actual registry entries/name tuples coexist. One envelope's object view,
/// key validation, emitter and hashing workspace are sequentially reused, not
/// multiplied by member count. Source strings/cursors/backing remain borrowed.
/// No policy ceiling or retained Catalog is treated as a memory demand.
pub fn registry_construction_extent(
  geometry : RegistryConstructionGeometry,
) -> RegistryConstructionExtent? {
  let { members, max_nodes, max_fields, } = geometry
  if members < 0 ||
    max_nodes < 0 ||
    max_fields < 0 ||
    max_fields > max_nodes ||
    (members > 0 && max_nodes == 0) {
    return None
  }
  let c = members.to_int64()
  let f = max_fields.to_int64()
  let counts : @shape.CollectionConstructionInventory = if members == 0 {
    // Original empty Registry + entries Array + names Map, not an empty
    // substitute for a populated Environment or another semantic role.
    {
      records: 1L,
      record_references: 3L,
      record_words: 2L,
      reference_arrays: 1L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: 0L,
    }
  } else {
    let child = @decode.indexed_child_construction_extent()
    let access = member_access_construction_extent()
    let keys = @shape.object_key_construction_counts(max_fields, 0, 6).unwrap()
    // Retained ContractEnvelope/Member/name tuple:3H10R2W per entry.
    // Fixed30H38R22W plus six shared indexed-child and one Member-access covers Registry/remaining limits/data records, fields and
    // hash tuples, bounded reader/lookup wrappers and
    // envelope-error controls. Envelope path depth is at most3 in this exact
    // Environment member position; it is not arbitrary decode ancestry.
    // Arrays: entries, allowed6, projected keys, required0, error path3
    // plus SAME shared key checker's pair arrays. No parallel Map tariff.
    {
      records: 30L +
      6L * child.record_headers +
      access.record_headers +
      3L * c +
      keys.pairs,
      record_references: 38L +
      6L * child.reference_slots +
      access.reference_slots +
      10L * c +
      2L * keys.pairs,
      record_words: 22L + 6L * child.scalar_words + access.scalar_words + 2L * c,
      reference_arrays: 5L + keys.pair_arrays.to_int64(),
      reference_items: c + f + keys.pairs + 9L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L + keys.maps.to_int64(),
      map_entries: c + f + keys.map_entries,
    }
  }
  let collections = @shape.collection_construction_extent(counts).unwrap()
  if members == 0 {
    return Some({
      record_headers: collections.record_headers,
      reference_slots: collections.reference_slots,
      scalar_words: collections.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  }
  // Each original hash helper returns before the next writer is constructed.
  // Node count, not configured depth/node maxima, bounds actual live Maps and
  // traversal. Two returned self-CID String71 alternatives may still coexist.
  let hashing = wire_hash_construction_extent(max_nodes).unwrap()
  Some({
    record_headers: collections.record_headers + hashing.record_headers,
    reference_slots: collections.reference_slots + hashing.reference_slots,
    scalar_words: collections.scalar_words + hashing.scalar_words,
    owned_utf16_units: hashing.owned_utf16_units,
    owned_wire_bytes: hashing.owned_wire_bytes,
  })
}

///|
/// Retain original registry records/arrays/name Map only after the synchronous
/// reader/emitter/hash frames return. Growth backing remains a conservative
/// upper bound; no input/body/string backing or physical ACK is released.
pub fn registry_retained_construction_extent(
  members : Int,
) -> RegistryConstructionExtent? {
  if members < 0 {
    return None
  }
  let c = members.to_int64()
  let v = @shape.collection_construction_extent({
    records: 1L + 3L * c,
    record_references: 3L + 10L * c,
    record_words: 2L + 2L * c,
    reference_arrays: 1L,
    reference_items: c,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: c,
  }).unwrap()
  Some({
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
