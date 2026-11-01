///|
/// Named logical KeyAdmission/Map construction storage, including old/new
/// backing during growth. Original keys are borrowed; no text is copied by
/// admit_key. This DATA is not a price, grant or backend/RSS supply proof.
pub(all) struct KeyAdmissionConstructionExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
/// owners bounds live key-admission objects; keys bounds all retained entries
/// across those objects. Duplicate probes do not create another entry. The
/// caller owns the lifetime proof for sum versus sequential reuse.
pub fn key_admission_construction_extent(
  owners : Int,
  keys : Int,
) -> KeyAdmissionConstructionExtent? {
  if owners < 0 || keys < 0 {
    return None
  }
  let o = owners.to_int64()
  guard map_construction_extent(o, keys.to_int64()) is Some(map) &&
    @counts.checked_nonnegative_add_product(map.record_headers, o, 1L)
    is Some(h) &&
    @counts.checked_nonnegative_add_product(map.reference_slots, o, 1L)
    is Some(r) else {
    return None
  }
  // KeyAdmission adds precisely its own record and Map reference. The linked
  // Map/Entry/bucket rule has one owner, shared with other actual Map domains.
  Some({
    record_headers: h,
    reference_slots: r,
    scalar_words: map.scalar_words,
  })
}
