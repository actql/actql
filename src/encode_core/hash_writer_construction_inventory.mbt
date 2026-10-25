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
/// append backing overlap is bounded by 12+3n; Map doubling overlap by 12d+6n.
/// Frames, entries and option carriers are counted separately from backing.
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
  let n = max_live_keys.to_int64()
  let d = max_depth.to_int64()
  // Writer + HashOutput + Hasher; four dynamic arrays (frames/state/words/
  // block), allowing one old backing each. Frame records and ordered-key Some
  // carriers; Map control/backings; Entry and two linked/bucket Some carriers.
  let owner_headers = 3L + 4L * 3L + 2L * d + 3L * d + 3L * n
  let owner_refs = 6L +
    4L +
    (12L + 3L * d) +
    2L * d +
    2L * d +
    (12L * d + 6L * n) +
    4L * n
  // State/words numeric backing and byte block: charge byte slots as scalar
  // words conservatively, never as references. Array wrapper length/capacity.
  let owner_words = 13L +
    8L +
    (12L + 3L * 8L) +
    (12L + 3L * 64L) * 2L +
    2L * d +
    5L * d +
    6L * n +
    (12L * d + 6L * n) // Empty bucket None tags are scalar storage too.
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
    record_headers: owner_headers + finish_headers + iterator_headers,
    reference_slots: owner_refs + finish_refs + iterator_refs,
    scalar_words: owner_words + finish_words + iterator_words,
    owned_utf16_units: finish_utf16,
    owned_wire_bytes: finish_wire,
  })
}
