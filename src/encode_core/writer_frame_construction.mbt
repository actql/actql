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

///|
/// Original Writer/frame/Map controls before one bounded step. Output sinks,
/// borrowed strings and serializer-owned cursors are separate inventories.
pub fn writer_next_frame_construction_extent(
  writer : Writer,
  additional_nodes : Int,
  additional_depth : Int,
) -> @shape.CollectionConstructionExtent? {
  if writer.closed || additional_nodes < 0 || additional_depth < 0 {
    return None
  }
  let nodes = writer.max_nodes -
    writer.remaining_nodes +
    Int::min(additional_nodes, writer.remaining_nodes)
  let depth = Int::max(
    writer.peak_depth,
    writer.frames.length() +
    Int::min(additional_depth, writer.max_depth - writer.frames.length()),
  )
  Some(writer_frame_construction_extent(nodes, depth))
}
