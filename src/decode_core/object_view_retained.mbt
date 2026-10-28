///|
/// Observe only the original selected view's retained Map/backing. No field
/// lookup, shape validation, path/String copy or new ObjectView is performed.
pub fn object_view_retained_extent(
  original : ObjectView,
) -> @shape.CollectionConstructionExtent? {
  guard @shape.map_retained_extent(
      1L,
      original.fields.capacity().to_int64(),
      original.fields.length().to_int64(),
    )
    is Some(map) else {
    return None
  }
  @shape.add_collection_construction_extents(map, {
    record_headers: 1L,
    reference_slots: 2L,
    scalar_words: 0L,
  })
}
