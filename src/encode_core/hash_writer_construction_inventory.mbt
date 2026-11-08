///|
/// Logical owned representation for one incremental hashing writer, including
/// final SHA-256 digest/hex scratch. Not heap/RSS and not a resource grant.
/// Input text/key strings and module SHA constants are borrowed. TextOutput,
/// buffered sinks and serializer-owned traversal stacks are excluded.
pub(all) struct HashWriterConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  owned_wire_bytes : Int64
} derive(Eq, Debug)

///|
/// Conservative constructor peak for both ordered and unordered object modes.
/// Each key insertion consumes a value node; hence at most max_nodes retained
/// Map entries, with at most max_depth simultaneously live frame Maps. Dynamic
/// append backing overlap is bounded by 12+3n. Map growth, entries and their
/// linked/bucket option carriers come from the shared collection owner.
/// Frame/ordered-key carriers remain separate from that Map inventory.
/// Fixed VM frames and opaque allocator bookkeeping are not represented here.
pub fn hash_writer_construction_inventory(
  max_nodes : Int,
  max_depth : Int,
) -> HashWriterConstructionInventory? {
  hash_writer_live_key_inventory(max_nodes, max_depth)
}

///|
/// Same owned writer constructor, given an independently proved upper bound
/// on simultaneously live object-Map keys. This is NOT a writer node limit.
/// General callers use max_nodes above; ancestry-aware synchronous emitters
/// may prove a smaller live-key bound while retaining their full node budget.
pub fn hash_writer_live_key_inventory(
  max_live_keys : Int,
  max_depth : Int,
) -> HashWriterConstructionInventory? {
  guard max_live_keys >= 0 && max_depth >= 0 else { return None }
  let frames = writer_frame_construction_extent(max_live_keys, max_depth)
  // HashOutput1H1R1W + Hasher1H3R3W, with its original state8/words64/
  // block64 arrays. Shared collection construction owns their growth backing.
  // The byte block keeps its existing conservative scalar-word classification.
  let sink = @shape.collection_construction_extent({
    records: 2L,
    record_references: 4L,
    record_words: 4L,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 3L,
    scalar_items: 8L + 64L + 64L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let owner = @shape.add_collection_construction_extents(frames, sink).unwrap()
  // SHA finish: length Bytes8; growing output Array32 + old backing; digest
  // Bytes32; hex builder and its backing, old/new String64 and digits16.
  // String/ordered-key resumable cursors, two one-character escape strings,
  // finite-number String25, metrics/usage tuple carriers are also live-safe.
  let finish_headers = 1L + 3L + 1L + 2L + 2L + 1L + 2L + 3L + 2L
  let finish_refs = 1L + 1L + 2L + 7L + 2L
  let finish_words = 2L + 1L + 16L + 5L + 6L
  let finish_wire = 8L + (12L + 3L * 32L) + 32L
  let finish_utf16 = 12L + 3L * 64L + 2L * 64L + 2L + 25L
  // FixedArray.iter().collect() in SHA initialization: borrowed ArrayView,
  // Iter record, closure + mutable index Ref, old/new size-hint Some and
  // yielded UInt Some. These allocated controls are not VM call frames.
  let iterator_headers = 8L
  let iterator_refs = 8L
  let iterator_words = 12L
  // Int inputs bound every product well below Int64.MAX; no unchecked
  // caller-sized Int64 multiplication or cumulative lifetime budget exists.
  Some({
    record_headers: owner.record_headers + finish_headers + iterator_headers,
    reference_slots: owner.reference_slots + finish_refs + iterator_refs,
    scalar_words: owner.scalar_words + finish_words + iterator_words,
    owned_utf16_units: finish_utf16,
    owned_wire_bytes: finish_wire,
  })
}

///|
/// The original hash sink and its next bounded frame/key additions, without
/// reserving configured node/depth ceilings. No output buffer is allocated by
/// this sink. Current writer cells also retain earlier frame-array peaks.
pub fn hash_writer_next_construction_inventory(
  writer : Writer,
  additional_nodes : Int,
  additional_depth : Int,
) -> HashWriterConstructionInventory? {
  guard !writer.closed &&
    writer.output is HashOutput(_) &&
    additional_nodes >= 0 &&
    additional_depth >= 0 else {
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
  hash_writer_live_key_inventory(nodes, depth)
}
