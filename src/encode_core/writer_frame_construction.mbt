///|
// SAME Writer/frame/ordered-key carrier and growing frame Array for every
// sink. Input key Strings are borrowed; the shared Map owner expands only
// simultaneous object/key multiplicity. Sink state remains separate.
fn writer_frame_construction_extent(
  live_keys : Int,
  depth : Int,
) -> @shape.CollectionConstructionExtent {
  let d = depth.to_int64()
  @shape.collection_construction_extent({
    records: 1L + 2L * d,
    record_references: 2L + 2L * d,
    record_words: 9L + 2L * d,
    reference_arrays: 1L,
    reference_items: d,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: d,
    map_entries: live_keys.to_int64(),
  }).unwrap()
}
