///|
/// Original score-declaration output and its sequential nested read overlap.
/// Counts and text lengths belong to the selected original score map only.
/// No score/domain/value admission, inferred identity or authority is supplied.
pub(all) struct RankingReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  retained_utf16_units : Int64
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn ranking_scores_construction_inventory(
  geometry : @decode.SubtreeGeometry,
  scores : Int,
  total_field_name_utf16_units : Int64,
  max_field_name_utf16_units : Int,
) -> RankingReadConstructionInventory? {
  let g = geometry
  if scores < 0 ||
    total_field_name_utf16_units < 0L ||
    max_field_name_utf16_units < 0 ||
    scores > g.fields {
    return None
  }
  guard @checking.scan_construction_extent(g) is Some(scan) &&
    @decode.closed_object_field_construction_extent(
      Some(g.max_fields),
      4,
      g.outer_depth.to_int64() + g.nodes.to_int64(),
    )
    is Some(contract_view) &&
    @decode.open_object_construction_extent(scores) is Some(root_view) else {
    return None
  }
  let n = scores.to_int64()
  // Per score: original child Cursor1H2R1W, DeclaredScore1H5R,
  // ScoreContract1H2R2W, Usage1H3W and Unqualified field1H1R1W.
  // Each outer key owns only its new "u:"+name String, not source text.
  // Transfer/RankingInput/Usage/soleSome4H10R4W retain the exact same bodies.
  let retained = @shape.collection_construction_extent({
    records: 6L * n + 4L,
    record_references: 10L * n + 10L,
    record_words: 7L * n + 4L,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 2L,
    map_entries: n,
  }).unwrap()
  // One inner declare_ranking_score result can coexist with the accumulating
  // outer Map: its RankingInput/Some/Ok3H9R2W and two original Maps (one key).
  // The final ranking_relation temporary adds its own empty Map and record.
  // Original two Budget/selected Limits, scalar/required/lookup/range/typed
  // failure and return alternatives form fixed36H32R42W; no new VM frames.
  let field = @decode.indexed_field_construction_extent()
  let child = @decode.indexed_child_construction_extent()
  let frame = @shape.collection_construction_extent({
    records: 40L + field.record_headers + 5L * child.record_headers,
    record_references: 48L + field.reference_slots + 5L * child.reference_slots,
    record_words: 44L + field.scalar_words + 5L * child.scalar_words,
    reference_arrays: 2L,
    reference_items: 6L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 3L,
    map_entries: 1L,
  }).unwrap()
  let mut scratch = scan
  for original in [root_view, contract_view, frame] {
    scratch = @shape.add_collection_construction_extents(scratch, original).unwrap()
  }
  Some({
    retained,
    scratch,
    retained_utf16_units: total_field_name_utf16_units + 2L * n,
    scratch_utf16_units: max_field_name_utf16_units.to_int64() + 2L,
  })
}
