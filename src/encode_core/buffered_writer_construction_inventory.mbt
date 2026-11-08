///|
/// One drained BufferedTextOutput transition. Input text and serializer frames
/// stay borrowed/owned by their original callers; retained prior fragments and
/// final concatenation are OUT. These are constructor quantities, not grants.
pub(all) struct BufferedWriterConstructionInventory {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
} derive(Eq, Debug)

///|
fn buffered_writer_construction_inventory(
  bytes : Int,
  retained_fragment_utf16 : Int,
  keys : Int,
  depth : Int,
) -> BufferedWriterConstructionInventory? {
  if bytes < 0 || retained_fragment_utf16 < 0 || keys < 0 || depth < 0 {
    return None
  }
  let frames = writer_frame_construction_extent(keys, depth)
  // Same current builder, old/new growth backing, drained String, ASCII
  // view and scalar/escape controls as TextOutput. BufferedText adds its
  // record (1H1R2W); drain replaces its builder with one fresh one-slot
  // builder (1H1R1W) while the old builder and returned String still coexist.
  // Native capacity is <=2B; its trimmed returned String is <=B, plus the
  // fresh one-slot backing. No reset proportional to historical capacity.
  // A caller may conservatively retain its already-observed fragment peak;
  // that is original history, not a configured policy-sized allocation.
  let peak = Int::max(bytes, retained_fragment_utf16).to_int64()
  Some({
    record_headers: frames.record_headers + 20L,
    reference_slots: frames.reference_slots + 11L,
    scalar_words: frames.scalar_words + 16L,
    owned_utf16_units: 3L * peak + 2L + Int::min(bytes, 257).to_int64() + 29L,
  })
}

///|
/// Initial empty writer/buffer only. Limits do not preallocate their ceilings.
pub fn buffered_writer_start_construction_inventory() -> BufferedWriterConstructionInventory {
  buffered_writer_construction_inventory(0, 0, 0, 0).unwrap()
}

///|
/// Before a single emission step, with the original buffer empty. One node or
/// key step can add at most one frame/key. Actual observed usage bounds these
/// controls without allocating the complete configured node/depth ceiling.
pub fn buffered_writer_next_construction_inventory(
  writer : Writer,
  fragment_bytes : Int,
  retained_fragment_utf16 : Int,
) -> BufferedWriterConstructionInventory? {
  guard !writer.closed &&
    writer.output is BufferedTextOutput(buffer) &&
    buffer.bytes == 0 &&
    fragment_bytes >= 0 &&
    retained_fragment_utf16 >= 0 &&
    fragment_bytes <= buffer.limit &&
    fragment_bytes <= writer.remaining_bytes else {
    return None
  }
  let nodes = writer.max_nodes - writer.remaining_nodes
  let keys = if nodes < writer.max_nodes { nodes + 1 } else { nodes }
  let next_depth = if writer.frames.length() < writer.max_depth {
    writer.frames.length() + 1
  } else {
    writer.frames.length()
  }
  // Native pop retains backing. Completed payloads are explicitly retired,
  // but the original maximum open depth still funds that backing.
  let depth = Int::max(writer.peak_depth, next_depth)
  buffered_writer_construction_inventory(
    fragment_bytes, retained_fragment_utf16, keys, depth,
  )
}

///|
/// The hashing variant owns the SAME bounded text builder beside its SHA
/// sink. Count their common frame storage once. reset() may retain the old
/// builder capacity, so the caller keeps its actual earlier fragment peak.
pub fn buffered_hash_writer_start_construction_inventory() -> HashWriterConstructionInventory {
  buffered_hash_writer_inventory(0, 0, 0, 0).unwrap()
}

///|
fn buffered_hash_writer_inventory(
  bytes : Int,
  peak : Int,
  nodes : Int,
  depth : Int,
) -> HashWriterConstructionInventory? {
  guard buffered_writer_construction_inventory(bytes, peak, nodes, depth)
    is Some(text) &&
    hash_writer_live_key_inventory(nodes, depth) is Some(hash) else {
    return None
  }
  let frames = writer_frame_construction_extent(nodes, depth)
  Some({
    record_headers: text.record_headers +
    hash.record_headers -
    frames.record_headers,
    reference_slots: text.reference_slots +
    hash.reference_slots -
    frames.reference_slots,
    scalar_words: text.scalar_words + hash.scalar_words - frames.scalar_words,
    owned_utf16_units: text.owned_utf16_units + hash.owned_utf16_units,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
pub fn buffered_hash_writer_next_construction_inventory(
  writer : Writer,
  fragment_bytes : Int,
  retained_fragment_utf16 : Int,
  additional_nodes : Int,
  additional_depth : Int,
) -> HashWriterConstructionInventory? {
  guard !writer.closed &&
    writer.output is BufferedHashOutput(buffer) &&
    fragment_bytes >= 0 &&
    retained_fragment_utf16 >= 0 &&
    additional_nodes >= 0 &&
    additional_depth >= 0 else {
    return None
  }
  let fragment = Int::min(
    fragment_bytes,
    Int::min(writer.remaining_bytes, buffer.limit - buffer.bytes),
  )
  guard writer_next_live_keys(writer, additional_nodes) is Some(nodes) else {
    return None
  }
  let depth = Int::max(
    writer.peak_depth,
    writer.frames.length() +
    Int::min(additional_depth, writer.max_depth - writer.frames.length()),
  )
  buffered_hash_writer_inventory(
    buffer.bytes + fragment,
    retained_fragment_utf16,
    nodes,
    depth,
  )
}
