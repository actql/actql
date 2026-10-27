///|
/// Complete original closed_object constructor storage. Actual supplied width
/// and the SAME key-check path own maps/pair arrays; allowed width is not a
/// bound on invalid input. Names/tree/Spans remain original borrows. These are
/// construction DATA, never closed-shape admission, a byte tariff or a grant.
pub fn closed_object_construction_extent(
  original : Cursor,
  allowed_fields : Int,
  root_path_depth : Int,
) -> @shape.CollectionConstructionExtent? {
  if allowed_fields < 0 || root_path_depth < 0 {
    return None
  }
  closed_object_field_construction_extent(
    object_length(original),
    allowed_fields,
    root_path_depth.to_int64(),
  )
}

///|
/// The SAME constructor recipe from already observed supplied width. None
/// denotes a non-Object; Some never substitutes the allowed width. Quantity
/// DATA alone is not a closed-shape verdict or permission.
pub fn closed_object_field_construction_extent(
  fields : Int?,
  allowed_fields : Int,
  root_path_depth : Int64,
) -> @shape.CollectionConstructionExtent? {
  if allowed_fields < 0 || root_path_depth < 0L || (fields is Some(n) && n < 0) {
    return None
  }
  let keys = match fields {
    None => None
    Some(count) =>
      @shape.object_key_construction_counts(count, 0, allowed_fields)
  }
  let (maps, entries, pair_arrays, pairs) = match keys {
    None => (0L, 0L, 0L, 0L)
    Some(k) =>
      (k.maps.to_int64(), k.map_entries, k.pair_arrays.to_int64(), k.pairs)
  }
  // ObjectView2R/Ok1R1W; original key issue+Err/selected pair/Field/Decode
  // issue+Err own6H8R6W. Two map projections own2 closures2R, each pair1R1W.
  // Keys/empty-required Arrays and selected pair Arrays precede open_object.
  // Alternatives are co-counted so early unknown/wrong-kind refusals retain
  // full original paths without claiming a successful ObjectView exists.
  let body : @shape.CollectionConstructionInventory = {
    records: 8L + object_view_result_controls.record_headers + pairs,
    record_references: 10L + object_view_result_controls.reference_slots + pairs,
    record_words: 6L + object_view_result_controls.scalar_words + pairs,
    reference_arrays: if fields is Some(_) {
      2L + pair_arrays
    } else {
      0L
    },
    reference_items: fields.unwrap_or(0).to_int64() + pairs,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: maps + (if fields is Some(_) { 1L } else { 0L }),
    map_entries: entries + fields.unwrap_or(0).to_int64(),
  }
  guard @shape.collection_construction_extent(body) is Some(body) &&
    @counts.checked_nonnegative_add_product(
      root_path_depth,
      if fields is Some(_) {
        1L
      } else {
        0L
      },
      1L,
    )
    is Some(path_depth) &&
    cursor_path_construction_extent(path_depth) is Some(path) else {
    return None
  }
  @shape.add_collection_construction_extents(body, path)
}
