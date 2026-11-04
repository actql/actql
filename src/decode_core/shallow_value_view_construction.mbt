///|
/// Peak for one existing view call, independently bounded by its possible
/// array width and object width. The two branch envelopes are deliberately
/// co-counted. Original indexed backing, keys and scalar text remain borrowed.
/// This is constructor DATA, not a view, validity claim or physical grant.
pub fn shallow_value_view_construction_extent(
  array_items : Int,
  object_fields : Int,
) -> @shape.CollectionConstructionExtent? {
  if array_items < 0 || object_fields < 0 {
    return None
  }
  let n = array_items.to_int64()
  // Array.map constructs one detached child Cursor per item, one closure and
  // one ValueView. ObjectValue additionally wraps the existing open_object.
  // Co-count one scalar view as well, including its boxed payload/tag.
  guard @shape.collection_construction_extent({
      records: n + 3L,
      record_references: 2L * n + 3L,
      record_words: n + 3L,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(array) &&
    open_object_construction_extent(object_fields) is Some(object) else {
    return None
  }
  @shape.add_collection_construction_extents(array, object)
}
