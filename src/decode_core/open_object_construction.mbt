///|
/// Original open_object success path for an observed Object width. The Map
/// borrows its original names/indices; wrong-kind/error paths are separately
/// owned by issue_construction_extent. These are DATA, never a shape verdict,
/// byte tariff, reservation or physical backing. The caller funds quote frames.
pub fn open_object_construction_extent(
  fields : Int,
) -> @shape.CollectionConstructionExtent? {
  if fields < 0 {
    return None
  }
  guard @shape.map_construction_extent(1L, fields.to_int64()) is Some(map) else {
    return None
  }
  @shape.add_collection_construction_extents(object_view_result_controls, {
    record_headers: map.record_headers,
    reference_slots: map.reference_slots,
    scalar_words: map.scalar_words,
  })
}

///|
// SAME ObjectView(cursor,fields)1H2R and returned Ok1H1R1W for open/closed.
let object_view_result_controls : @shape.CollectionConstructionExtent = {
  record_headers: 2L,
  reference_slots: 3L,
  scalar_words: 1L,
}
