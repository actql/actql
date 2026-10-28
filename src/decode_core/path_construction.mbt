///|
/// Original cursor_path/path_at construction only. The input tree, field
/// names and Spans remain borrowed. Key/Index alternatives conservatively
/// co-count their payload slots; the same Array owner prices growth/reversal.
/// This is DATA, not a location verdict, Resource grant or physical backing.
pub fn cursor_path_construction_extent(
  max_segments : Int64,
) -> @shape.CollectionConstructionExtent? {
  guard @counts.checked_nonnegative_add_product(0L, max_segments, 2L)
    is Some(words) else {
    return None
  }
  let path : @shape.CollectionConstructionInventory = {
    records: max_segments,
    record_references: max_segments,
    record_words: words,
    reference_arrays: 1L,
    reference_items: max_segments,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }
  @shape.collection_construction_extent(path)
}

///|
/// Exact original ancestry without constructing path variants or arrays.
/// Work counts actual parent-record visits, not validation or processCPU.
pub fn observe_cursor_path_depth(cursor : Cursor) -> (Int, Int64) {
  let mut index = cursor.index
  let mut depth = 0
  let mut work = 0L
  while true {
    work += 1L
    let parent = cursor.tree[index].parent
    if parent < 0 {
      break
    }
    depth += 1
    index = parent
  }
  (depth, work)
}
