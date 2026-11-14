///|
/// Construction of the original measuring Writer, not a byte-output sink.
/// Arguments describe actual simultaneously live keys and container depth;
/// they are not codec policy allowances or permission to construct the writer.
/// Input Strings and emitter/scanner continuations remain separately owned.
pub fn measuring_writer_construction_extent(
  live_keys : Int,
  depth : Int,
) -> @shape.CollectionConstructionExtent? {
  if live_keys < 0 || depth < 0 {
    return None
  }
  // MeasureOutput is a payload-free variant. The Writer/frame owner already
  // includes Writer.output. Conservatively count a sink header, plus the
  // three-word tuple returned by finish_measurement_usage.
  let frames = writer_frame_construction_extent(live_keys, depth)
  guard @shape.collection_construction_extent({
      records: 2L,
      record_references: 0L,
      record_words: 3L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(finish) else {
    return None
  }
  @shape.add_collection_construction_extents(frames, finish)
}
