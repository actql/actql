///|
/// Retained pinned Array wrapper/current backing after construction returns.
/// Supply the original observed buffer slots, not a policy or semantic limit.
/// Old growth buffers and transient constructors have a separate peak recipe.
pub fn reference_array_retained_extent(
  arrays : Int64,
  buffer_slots : Int64,
) -> CollectionConstructionExtent? {
  guard @counts.checked_nonnegative_add_product(0L, arrays, 2L) is Some(h) &&
    @counts.checked_nonnegative_add_product(arrays, buffer_slots, 1L) is Some(r) &&
    @counts.checked_nonnegative_add_product(0L, arrays, 2L) is Some(w) else {
    return None
  }
  Some({ record_headers: h, reference_slots: r, scalar_words: w, })
}

///|
/// Same pinned linked Map after growth returns: Map/current bucket2H2R6W,
/// original Entry and bucket/link Some3H5R5W each. Keys/values are borrowed.
/// The original Map supplies capacity/entry counts; this DATA grants nothing
/// and is not a VM/RSS measurement or a second construction/growth policy.
pub fn map_retained_extent(
  maps : Int64,
  bucket_slots : Int64,
  entries : Int64,
) -> CollectionConstructionExtent? {
  guard @counts.checked_nonnegative_add_product(0L, maps, 2L) is Some(h) &&
    @counts.checked_nonnegative_add_product(h, entries, 3L) is Some(h) &&
    @counts.checked_nonnegative_add_product(bucket_slots, maps, 2L) is Some(r) &&
    @counts.checked_nonnegative_add_product(r, entries, 5L) is Some(r) &&
    @counts.checked_nonnegative_add_product(0L, maps, 6L) is Some(w) &&
    @counts.checked_nonnegative_add_product(w, entries, 5L) is Some(w) else {
    return None
  }
  Some({ record_headers: h, reference_slots: r, scalar_words: w, })
}

///|
/// Additional backing for one push into the SAME pinned Array. The existing
/// wrapper/current buffer stay charged to their original holder. A non-growing
/// push allocates no backing; doubling/fallback and the empty minimum are
/// bounded here, alongside the existing collection recipe. JS hidden backing
/// is covered by the same logical bound, not measured by Array.capacity().
pub fn reference_array_push_construction_extent(
  length : Int,
  capacity : Int,
) -> CollectionConstructionExtent? {
  if length < 0 || capacity < length {
    return None
  }
  if length < capacity {
    return Some({ record_headers: 0L, reference_slots: 0L, scalar_words: 0L, })
  }
  Some({
    record_headers: 1L,
    reference_slots: Int64::max(8L, 2L * (length.to_int64() + 1L)),
    scalar_words: 0L,
  })
}
