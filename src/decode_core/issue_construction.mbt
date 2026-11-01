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
  issue_path_construction_extent(max_path_segments.to_int64())
}

///|
/// Same Issue/Err/path owner with checked wide quantity DATA. This does not
/// allocate a path or assert that a Cursor or semantic Issue exists.
pub fn issue_path_construction_extent(
  max_path_segments : Int64,
) -> @shape.CollectionConstructionExtent? {
  if max_path_segments < 0L {
    return None
  }
  guard cursor_path_construction_extent(max_path_segments) is Some(path) else {
    return None
  }
  // The SAME path owner checks every wide product/addition. Issue1H2R and
  // returned Err1H1R2W overlap that one path; names/tree remain borrowed.
  @shape.add_collection_construction_extents(path, {
    record_headers: 2L,
    reference_slots: 3L,
    scalar_words: 2L,
  })
}
