///|
/// Retained Key and the long-form field Cursor. The passed source Cursor,
/// field String and indexed tree/usage stay original borrowed owners. A short
/// form can share its source/field Cursor; this upper includes both forms.
pub fn read_retained_construction_extent() -> @shape.CollectionConstructionExtent {
  { record_headers: 2L, reference_slots: 5L, scalar_words: 5L, }
}

///|
/// Complete original read constructor overlap, including actual wide malformed
/// Objects and typed diagnostic paths from observed width/depth DATA. No order field/type resolution, NFC,
/// admission, capacity policy or byte tariff is introduced here. The caller
/// backs the passed original Cursor and this quantity frame before entry.
pub fn read_construction_extent(
  fields : Int,
  root_path_depth : Int64,
) -> @shape.CollectionConstructionExtent? {
  if fields < 0 ||
    root_path_depth < 0L ||
    root_path_depth == 9223372036854775807L {
    return None
  }
  guard @decode.open_object_construction_extent(fields) is Some(open) &&
    @decode.closed_object_field_construction_extent(
      Some(fields),
      3,
      root_path_depth,
    )
    is Some(closed) &&
    @decode.issue_path_construction_extent(root_path_depth + 1L) is Some(issue) else {
    return None
  }
  let child = @decode.indexed_child_construction_extent()
  // Original field-name map result/closure2H1R1W; one growing names Array and the three-name allowed literal.
  // Key1H3R4W; selected five-field tuple1H2R3W; source Issue1H2R1W,
  // Decode kind+diagnostic Some2H2R2W; Stop/Ok/Err3H3R3W; four scalar
  // text-result alternatives4H4R4W, three required-result Ok3H3R3W and
  // the boxed IssueKind alternative1R1W. The four original child sites are the
  // short-form lookup and long-form required(field,dir,nulls); their actual
  // retained field Cursor is already among those SAME Decode inventories.
  guard @shape.collection_construction_extent({
      records: 17L + 4L * child.record_headers,
      record_references: 21L + 4L * child.reference_slots,
      record_words: 22L + 4L * child.scalar_words,
      reference_arrays: 2L,
      reference_items: fields.to_int64() + 3L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(controls) &&
    @shape.add_collection_construction_extents(open, closed) is Some(body) &&
    @shape.add_collection_construction_extents(body, controls) is Some(body) else {
    return None
  }
  @shape.add_collection_construction_extents(body, issue)
}
