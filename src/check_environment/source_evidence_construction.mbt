///|
/// Constructor peak of the original Connector/Local snapshot partition call.
/// The SAME Member supplies actual object width and original path depth. The
/// allowed-field count never bounds malformed supplied width. Body Strings,
/// CIDs and the admitted tree stay borrowed. This is quantity DATA, not a
/// selector verdict, byte tariff, resource grant or complete Snapshot recipe.
pub fn connector_source_snapshot_selector_construction(
  original : Member,
) -> @shape.CollectionConstructionExtent {
  let body = member_body(original)
  let supplied = @decode.object_length(body)
  let (depth, _) = @decode.observe_cursor_path_depth(body)
  let allowed = connector_snapshot_member_fields()
  let closed = @decode.closed_object_field_construction_extent(
    supplied,
    allowed.length(),
    depth.to_int64(),
  ).unwrap()
  let opened = match supplied {
    Some(width) => @decode.open_object_construction_extent(width).unwrap()
    None => @decode.issue_construction_extent(depth).unwrap()
  }
  // The first source_ref ObjectView returns before the closed view starts.
  // All later text reads borrow that SAME closed view, never another Map.
  let view = @shape.CollectionConstructionExtent::{
    record_headers: Int64::max(closed.record_headers, opened.record_headers),
    reference_slots: Int64::max(closed.reference_slots, opened.reference_slots),
    scalar_words: Int64::max(closed.scalar_words, opened.scalar_words),
  }
  // Caller-owned Arrays: original allowed names, four CID names, four retained
  // CID values, and five classification alternatives. No String body copies.
  // Co-count fixed alternatives: selector/Some/Ok3H8R2W, CID view/iterator/
  // closure/index/Char/predicate6H4R5W, required/text/Option/expected4H4R4W,
  // and Array iterator/closure/index/element/predicate5H4R3W. These are the
  // named boxed construction families, not measured invocations or allocations.
  let caller = @shape.collection_construction_extent({
    records: 3L + 6L + 4L + 5L,
    record_references: 8L + 4L + 4L + 4L,
    record_words: 2L + 5L + 4L + 3L,
    reference_arrays: 4L,
    reference_items: allowed.length().to_int64() + 4L + 4L + 5L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  // required/text retain their original typed failures and detached field
  // path. Presence, scalar kind, every CID and final role check still execute.
  let child = @decode.indexed_child_construction_extent()
  let issue = @decode.issue_path_construction_extent(depth.to_int64() + 1L).unwrap()
  @shape.add_collection_construction_extents(
    view,
    @shape.add_collection_construction_extents(
      caller,
      @shape.add_collection_construction_extents(child, issue).unwrap(),
    ).unwrap(),
  ).unwrap()
}
