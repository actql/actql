///|
priv struct ReferenceRouteConstruction {
  routes : Int
  field_hops : Int
  all_hops : Int
  max_hops : Int
}

///|
pub(all) struct CatalogReferenceGeometry {
  catalogs : Int
  members : Int
  member_nodes : Int
  max_member_nodes : Int
} derive(Eq, Debug)

///|
/// Original Catalog membership and cached admitted member node counts only.
/// Count every occurrence, including repeated target references; no body walk,
/// parse/hash, role admission, deduplication or policy ceiling is substituted.
pub fn observe_reference_construction_geometry(
  contents : CatalogContents,
) -> CatalogReferenceGeometry {
  let mut members = 0
  let mut nodes = 0
  let mut largest = 0
  for catalog in contents.entries {
    for is_view in [true, false] {
      let items = if is_view { catalog.views } else { catalog.commands }
      for item in items {
        members += 1
        nodes += item.entry.nodes
        largest = Int::max(largest, item.entry.nodes)
      }
    }
  }
  {
    catalogs: contents.entries.length(),
    members,
    member_nodes: nodes,
    max_member_nodes: largest,
  }
}

///|
fn reference_geometry_valid(g : CatalogReferenceGeometry) -> Bool {
  g.catalogs >= 0 &&
  g.members >= 0 &&
  g.member_nodes >= 0 &&
  g.max_member_nodes >= 0 &&
  g.max_member_nodes <= g.member_nodes &&
  (if g.members == 0 {
    g.member_nodes == 0 && g.max_member_nodes == 0
  } else {
    g.catalogs > 0 && g.max_member_nodes > 0 && g.member_nodes >= g.members
  })
}

///|
/// Generated prefix-disjoint terminal routes each require an object and three
/// nonempty Strings. Thus actual owned nodes/4 bounds successful references,
/// even on a later typed refusal. Pending traversal is max_hops+1, because
/// RefEach visits one original element at a time. No row/work ceiling is size.
pub fn catalog_reference_construction_extent(
  g : CatalogReferenceGeometry,
) -> RegistryConstructionExtent? {
  if !reference_geometry_valid(g) {
    return None
  }
  let route = catalog_reference_route_construction()
  let r = route.routes.to_int64()
  let h = route.all_hops.to_int64()
  let f = route.field_hops.to_int64()
  let members = g.members.to_int64()
  let refs = g.member_nodes.to_int64() / 4L
  let pending = (route.max_hops + 1).to_int64()
  let counts : @shape.CollectionConstructionInventory = if g.members == 0 {
    // The original reader still constructs its full route table and two empty
    // Maps. Only member-dependent traversal/key/control storage is absent.
    {
      records: 6L + r + f,
      record_references: 13L + 2L * r + f,
      record_words: 3L + r + f,
      reference_arrays: r + 2L,
      reference_items: h + r,
      scalar_arrays: 1L,
      scalar_items: if g.catalogs == 0 {
        0L
      } else {
        2L
      },
      maps: 2L,
      map_entries: 0L,
    }
  } else {
    let child = @decode.indexed_child_construction_extent()
    let field = @decode.indexed_field_construction_extent()
    let keys = @shape.object_key_construction_counts(g.max_member_nodes, 0, 3).unwrap()
    // Reader/result2H8R2W; retained reference+Cursor2H6R1W, member range1H2W,
    // pending frame+Cursor2H3R4W. Route/hop records derive from the generator.
    // Fixed helpers include four indexed child sites and the shared field
    // accessor, ObjectViews/key wrappers, resolver carriers, length/tree-index
    // Options and bounded error path9 controls. Sequential alternatives are
    // deliberately co-counted, not claimed as minimum or measured heap/RSS.
    {
      records: 40L +
      4L * child.record_headers +
      field.record_headers +
      r +
      f +
      2L * refs +
      members +
      2L * pending +
      keys.pairs,
      record_references: 44L +
      4L * child.reference_slots +
      field.reference_slots +
      2L * r +
      f +
      6L * refs +
      3L * pending +
      2L * keys.pairs,
      record_words: 32L +
      4L * child.scalar_words +
      field.scalar_words +
      r +
      f +
      refs +
      2L * members +
      4L * pending,
      reference_arrays: 9L + r + keys.pair_arrays.to_int64(),
      reference_items: refs +
      pending +
      g.max_member_nodes.to_int64() +
      18L +
      h +
      r +
      keys.pairs,
      scalar_arrays: 1L,
      scalar_items: 2L,
      maps: 3L + keys.maps.to_int64(),
      map_entries: refs +
      members +
      g.max_member_nodes.to_int64() +
      keys.map_entries,
    }
  }
  let v = @shape.collection_construction_extent(counts).unwrap()
  Some({
    record_headers: v.record_headers,
    reference_slots: v.reference_slots,
    scalar_words: v.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
/// Original returned reference/root/Member-range records only, after the
/// synchronous route/key/traversal frame returned. Input bodies stay borrowed.
pub fn catalog_reference_retained_extent(
  g : CatalogReferenceGeometry,
) -> RegistryConstructionExtent? {
  if !reference_geometry_valid(g) {
    return None
  }
  let r = g.member_nodes.to_int64() / 4L
  let m = g.members.to_int64()
  let v = @shape.collection_construction_extent({
    records: 1L + 2L * r + m,
    record_references: 4L + 6L * r,
    record_words: 1L + r + 2L * m,
    reference_arrays: 1L,
    reference_items: r,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: r + m,
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
pub fn reference_construction_observation_work(
  contents : CatalogContents,
) -> Int64 {
  let environment = contents.registry.environment
  3L +
  contents.entries.length().to_int64() +
  member_count(environment, SourceViews).to_int64() +
  member_count(environment, CommandContracts).to_int64()
}
