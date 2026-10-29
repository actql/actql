///|
pub(all) struct CatalogConstructionGeometry {
  catalogs : Int
  indexed_members : Int
  body_nodes : Int
  max_nodes : Int
  max_fields : Int
} derive(Eq, Debug)

///|
/// Four section measurements and original disjoint member geometry only. No
/// body parse/hash or policy maxima. Admitted section members/nodes are disjoint
/// subsets of this original Environment's Int-bounded members/tree nodes.
pub fn observe_catalog_construction_geometry(
  registry : ContractRegistry,
) -> CatalogConstructionGeometry {
  let environment = registry.environment
  let count = member_count(environment, ConnectorCatalogs)
  let indexed = member_count(environment, SourceViews) +
    member_count(environment, CommandContracts) +
    member_count(environment, ContractRegistry)
  let mut nodes = 0
  let mut largest = 0
  let mut fields = 0
  for entry in environment.sections[position(ConnectorCatalogs)] {
    nodes += entry.nodes
    largest = Int::max(largest, entry.nodes)
    fields = Int::max(fields, @decode.object_length(entry.cursor).unwrap())
  }
  {
    catalogs: count,
    indexed_members: indexed,
    body_nodes: nodes,
    max_nodes: largest,
    max_fields: fields,
  }
}

///|
/// Counts belong to the original Catalog reader. All Int inputs make the
/// linear count expressions Int64-safe; collection/hash owners check their
/// expansion. Retained occurrences use actual total Catalog nodes as an upper
/// bound, never a configured row/member/depth ceiling.
pub fn catalog_contents_construction_extent(
  g : CatalogConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !catalog_construction_geometry_valid(g) {
    return None
  }
  let { catalogs, indexed_members, body_nodes, max_nodes, max_fields, } = g
  let c = catalogs.to_int64()
  let i = indexed_members.to_int64()
  let d = body_nodes.to_int64()
  let n = max_nodes.to_int64()
  let f = max_fields.to_int64()
  let j = Int64::min(i, d)
  let counts : @shape.CollectionConstructionInventory = if catalogs == 0 {
    // Real empty Contents or original derived-membership refusal. Eight empty
    // index/used/selector Maps are still constructed, not replaced by no DATA.
    {
      records: 4L + i,
      record_references: 4L + 2L * i,
      record_words: 4L + 2L * i,
      reference_arrays: 3L,
      reference_items: 6L,
      scalar_arrays: 1L,
      scalar_items: 3L,
      maps: 8L,
      map_entries: i,
    }
  } else {
    let child = @decode.indexed_child_construction_extent()
    let access = member_access_construction_extent()
    let keys = @shape.object_key_construction_counts(max_fields, 0, 7).unwrap()
    // Catalog+Member2H10R2W per Catalog; one indexed Member1H2R2W per
    // derived member; new full-hash String71 per used identity. Header/child
    // views,14 shared indexed-child lookup sites, selector tuples, four hash-result tuples,
    // options/results and bounded depth5 error paths:55H59R46W, plus14
    // shared child accesses and two Member access wrappers =117H121R106W.
    // Maps: index3,used3,connector1,command1,per-Catalog contracts, header+child
    // views and SAME key checker. Lists retain original matched Members.
    {
      records: 55L +
      14L * child.record_headers +
      2L * access.record_headers +
      2L * c +
      i +
      j +
      keys.pairs,
      record_references: 59L +
      14L * child.reference_slots +
      2L * access.reference_slots +
      10L * c +
      2L * i +
      2L * keys.pairs,
      record_words: 46L +
      14L * child.scalar_words +
      2L * access.scalar_words +
      2L * c +
      2L * i,
      reference_arrays: 7L + 2L * c + keys.pair_arrays.to_int64(),
      reference_items: 18L + c + d + f + keys.pairs,
      scalar_arrays: 1L,
      scalar_items: 3L,
      maps: 10L + c + keys.maps.to_int64(),
      map_entries: i + 2L * j + c + d + f + n + keys.map_entries,
    }
  }
  let v = @shape.collection_construction_extent(counts).unwrap()
  if catalogs == 0 {
    return Some({
      record_headers: v.record_headers,
      reference_slots: v.reference_slots,
      scalar_words: v.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
  }
  let hash = wire_hash_construction_extent(max_nodes).unwrap()
  Some({
    record_headers: v.record_headers + hash.record_headers,
    reference_slots: v.reference_slots + hash.reference_slots,
    scalar_words: v.scalar_words + hash.scalar_words,
    owned_utf16_units: hash.owned_utf16_units + 71L * (j + 1L),
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
/// Returned Catalog/Member/membership containers after the hash/key/index
/// frames return. Retain every indexed Member conservatively and original
/// growth backing; original Environment/registry is held by the same parent.
pub fn catalog_contents_retained_extent(
  g : CatalogConstructionGeometry,
) -> RegistryConstructionExtent? {
  if !catalog_construction_geometry_valid(g) {
    return None
  }
  let c = g.catalogs.to_int64()
  let i = g.indexed_members.to_int64()
  let d = g.body_nodes.to_int64()
  let v = @shape.collection_construction_extent({
    records: 1L + 2L * c + i,
    record_references: 2L + 10L * c + 2L * i,
    record_words: 3L + 2L * c + 2L * i,
    reference_arrays: 1L + 2L * c,
    reference_items: c + d,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: c,
    map_entries: d,
  }).unwrap()
  Some({
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn catalog_construction_geometry_valid(g : CatalogConstructionGeometry) -> Bool {
  g.catalogs >= 0 &&
  g.indexed_members >= 0 &&
  g.body_nodes >= 0 &&
  g.max_nodes >= 0 &&
  g.max_fields >= 0 &&
  g.max_fields <= g.max_nodes &&
  (g.catalogs == 0 || (g.max_nodes > 0 && g.body_nodes >= g.max_nodes))
}
