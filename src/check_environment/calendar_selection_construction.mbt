///|
/// Original calendar-selection reader overlap. Policy names/Strings and its
/// immutable decoder index remain borrowed. The selected four-field body is
/// checked before closed_object; an invalid wider body returns before that
/// constructor. These quantities do not select a profile or admit Calendar.
pub fn calendar_selection_construction_extent(
  policy_fields : Int,
  policy_path_depth : Int,
) -> @shape.CollectionConstructionExtent? {
  if policy_fields < 0 || policy_path_depth < 0 {
    return None
  }
  guard @decode.open_object_construction_extent(policy_fields) is Some(policy) &&
    @decode.closed_object_field_construction_extent(
      Some(4),
      4,
      policy_path_depth.to_int64() + 1L,
    )
    is Some(selected) &&
    @decode.issue_path_construction_extent(policy_path_depth.to_int64() + 2L)
    is Some(issue) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  // Six original lookups: calendar, four String fields and retained pin.
  // Four scalar outcomes4H4R4W; Stop/catch alternatives2H1R2W; original
  // fields tuple/Some2H5R1W; two length Some2H4W; Selection/Ok2H5R2W.
  // Allowed names and the four scalar lengths have their own original Arrays.
  let frame = @shape.collection_construction_extent({
    records: 12L + 6L * child.record_headers,
    record_references: 15L + 6L * child.reference_slots,
    record_words: 13L + 6L * child.scalar_words,
    reference_arrays: 1L,
    reference_items: 4L,
    scalar_arrays: 1L,
    scalar_items: 4L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  @shape.add_collection_construction_extents(
    policy,
    @shape.add_collection_construction_extents(
      selected,
      @shape.add_collection_construction_extents(
        frame,
        @shape.add_collection_construction_extents(issue, issue).unwrap(),
      ).unwrap(),
    ).unwrap(),
  )
}
