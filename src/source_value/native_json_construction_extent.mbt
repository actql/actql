///|
/// Construction inventory for admit_captured_json under the fixed Host's
/// detached native JSON projections. This is DATA, not an admitted shape or
/// permission. In particular number_text is that native finite binary64's
/// shortest spelling (at most25 characters), not an arbitrary source token.
/// Text and keys borrow the SAME captured input until this constructor returns.
pub fn captured_json_construction_extent(
  max_nodes : Int,
  max_depth : Int,
  normalize_keys? : Bool = false,
  key_units? : Int64 = 0L,
  max_key_units? : Int = 0,
) -> JsonConstructionExtent? {
  if max_nodes < 1 || max_depth < 1 {
    return None
  }
  let frames = Int::min(max_nodes, max_depth)
  guard json_construction_extent(1, max_nodes, max_depth, normalize_keys=false)
    is Some(tree) &&
    @shape.key_admission_construction_extent(max_nodes, max_nodes)
    is Some(all_keys) &&
    @shape.key_admission_construction_extent(frames, max_nodes)
    is Some(live_keys) &&
    json_construction_extent(25, 1, 1, normalize_keys=false) is Some(number) else {
    return None
  }
  // Reuse the existing Node/Value/Field/container/ancestry representation.
  // NativeObject retains KeyAdmission only on an open NativeJsonFrame; its
  // completed Node owns fields, never the seen Map. Replace only that named
  // lifetime component, preserving all entries and original growth overlap.
  // One native keys FixedArray per open object also borrows up to all input
  // key references. Scalar Number parsers run serially, not one per held row.
  let native : JsonConstructionExtent = {
    record_headers: tree.record_headers -
    all_keys.record_headers +
    live_keys.record_headers +
    frames.to_int64() +
    number.record_headers,
    reference_slots: tree.reference_slots -
    all_keys.reference_slots +
    live_keys.reference_slots +
    max_nodes.to_int64() +
    number.reference_slots,
    scalar_words: tree.scalar_words -
    all_keys.scalar_words +
    live_keys.scalar_words +
    number.scalar_words,
    // There is no quoted whole-document String builder, input byte buffer
    // or copied key/Text backing in native admission. Only this one native
    // Number spelling plus its actual scalar parser workspace is constructed.
    owned_utf16_units: 25L + number.owned_utf16_units,
  }
  if !normalize_keys {
    return Some(native)
  }
  if key_units < 0L || max_key_units < 0 || max_key_units.to_int64() > key_units {
    return None
  }
  guard @canonical.nfc_lf_construction_scratch_extent(max_key_units)
    is Some(normalization) &&
    @canonical.nfc_lf_retained_output_units(key_units) is Some(output) &&
    @counts.checked_nonnegative_add_product(
      native.owned_utf16_units,
      normalization.owned_utf16_units,
      1L,
    )
    is Some(backing) &&
    @counts.checked_nonnegative_add_product(backing, output, 1L)
    is Some(backing) else {
    return None
  }
  // Only one original key is normalized at a time. The SAME canonical Owner
  // supplies scratch and cumulative output separately. The shared structural
  // envelope already covers returned key String records; input Text stays
  // borrowed. Program literal-key exceptions normalize fewer keys, never more.
  Some({
    record_headers: native.record_headers + normalization.record_headers,
    reference_slots: native.reference_slots + normalization.reference_slots,
    scalar_words: native.scalar_words + normalization.scalar_words,
    owned_utf16_units: backing,
  })
}
