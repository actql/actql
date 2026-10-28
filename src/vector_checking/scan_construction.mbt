///|
/// Explicit dynamic work of the original synchronous scan. The Budget,
/// input tree/text and opaque VM/GC backing remain at their old owners.
pub fn scan_construction_extent(
  geometry : @decode.SubtreeGeometry,
) -> @shape.CollectionConstructionExtent? {
  let g = geometry
  if g.nodes < 1 ||
    g.fields < 0 ||
    g.max_fields < 0 ||
    g.max_array_items < 0 ||
    g.outer_depth < 0 {
    return None
  }
  let n = g.nodes.to_int64()
  guard @decode.open_object_construction_extent(g.max_fields) is Some(view) &&
    @decode.issue_path_construction_extent(g.outer_depth.to_int64() + n)
    is Some(path) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  let utf8 = @scalar.utf8_length_admission_construction_units()
  // Pending(Cursor,depth) and original child Cursor2N H3N R2N W. One
  // Array/object-key projection coexists with that stack, not one per node.
  // Five current view alternatives5H3R7W, popSome1H1R1W, names-result1H1R1W
  // and two original reverse-iterator alternatives6H6R4W are co-counted once.
  let frame = @shape.collection_construction_extent({
    records: 2L * n + 13L + child.record_headers + utf8.0,
    record_references: 3L * n + 11L + child.reference_slots + utf8.1,
    record_words: 2L * n + 13L + child.scalar_words + utf8.2,
    reference_arrays: 2L,
    reference_items: n + Int::max(g.max_fields, g.max_array_items).to_int64(),
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  @shape.add_collection_construction_extents(
    frame,
    @shape.add_collection_construction_extents(
      view,
      @shape.add_collection_construction_extents(path, path).unwrap(),
    ).unwrap(),
  )
}
