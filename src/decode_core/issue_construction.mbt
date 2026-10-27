///|
/// One original decoder Issue/Err and its detached path. The admitted tree,
/// field-name Strings, source span and Edge bodies remain borrowed. path_at
/// uses one growable Array and an in-place reverse, not another path copy.
/// This is logical constructor DATA, not an Issue, verdict or allocation.
pub fn issue_construction_extent(
  max_path_segments : Int,
) -> @shape.CollectionConstructionExtent? {
  if max_path_segments < 0 {
    return None
  }
  let d = max_path_segments.to_int64()
  // A segment can retain a Key reference or an Index payload. Componentwise
  // bounds keep both alternatives without copying their original backing.
  @shape.collection_construction_extent({
    records: 2L + d,
    record_references: 3L + d,
    record_words: 2L + 2L * d,
    reference_arrays: 1L,
    reference_items: d,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}
