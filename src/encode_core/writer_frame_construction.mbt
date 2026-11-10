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
// Live unordered Maps, not cumulative value nodes, own actual key entries.
// One pending key can precede its value-node admission at the next boundary.
fn writer_next_live_keys(writer : Writer, additional_nodes : Int) -> Int? {
  let mut keys = 0L
  for frame in writer.frames {
    match frame {
      ObjectKey(_, map) | ObjectValue(map) => keys += map.length().to_int64()
      _ => ()
    }
  }
  let next = keys + additional_nodes.to_int64() + 1L
  if next < 0L || next > 2147483647L {
    None
  } else {
    Some(next.to_int())
  }
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
  guard writer_next_live_keys(writer, additional_nodes) is Some(nodes) else {
    return None
  }
  let depth = Int::max(
    writer.peak_depth,
    writer.frames.length() +
    Int::min(additional_depth, writer.max_depth - writer.frames.length()),
  )
  Some(writer_frame_construction_extent(nodes, depth))
}
