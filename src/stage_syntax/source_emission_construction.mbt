///|
/// Existing admitted-source emitter traversal, excluding its separately owned
/// Writer and original indexed tree. This describes emit_body, not semantic
/// checking or another encoder. Node count bounds every edge and stack slot.
pub fn admitted_source_emission_construction_extent(
  nodes : Int,
) -> @shape.CollectionConstructionExtent? {
  if nodes < 1 {
    return None
  }
  let n = nodes.to_int64()
  // Emit plus ArrayNext/ObjectNext allocate at most three work variants per
  // visited node, each with one Cursor reference and at most two scalar words.
  // The single stack retains at most two entries per node. Include pop's
  // returned Some and the fixed traversal frame alongside the complete stack.
  guard @shape.collection_construction_extent({
      records: 3L * n + 2L,
      record_references: 3L * n + 3L,
      record_words: 6L * n + 2L,
      reference_arrays: 1L,
      reference_items: 2L * n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(work) &&
    @wire.shallow_value_view_construction_extent(nodes - 1, nodes - 1)
    is Some(view) &&
    @shape.scale_collection_construction_extent(
      @wire.indexed_child_construction_extent(),
      n,
    )
    is Some(children) &&
    @shape.scale_collection_construction_extent(
      @wire.indexed_field_construction_extent(),
      n,
    )
    is Some(fields) else {
    return None
  }
  // Each edge uses one of the two accessors. Both complete families are
  // co-counted, so pending Cursor wrappers stay funded beside the next view.
  @shape.compose_collection_construction_extents([work, view, children, fields])
}
