///|
/// Original read's logical constructor storage. The supplied input String is
/// borrowed; successful output owns decoded names and reconstructed text.
/// Quantities do not admit a Reference or issue bytes/resources/permission.
pub(all) struct ReferenceReadConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  retained_utf16_units : Int64
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
/// Use the SAME actual source_ref UTF16 length, not max_bytes or another field.
/// Invalid-input alternatives are bounded too. One NFC and one UTF8 workspace
/// suffice for the sequential original calls; no per-character control copies.
/// Caller quotation/input/VM frames, work and physical supply remain separate.
pub fn reference_read_construction_inventory(
  input_utf16_units : Int,
) -> ReferenceReadConstructionInventory? {
  guard @canonical.nfc_lf_construction_extent(input_utf16_units) is Some(nfc) else {
    return None
  }
  let u = input_utf16_units.to_int64()
  let parts = reference_parts_construction_extent()
  let (utf8_h, utf8_r, utf8_w) = @scalar.utf8_length_admission_construction_units()
  // Split/take/collection controls10H11R9W: two active borrowed views2H2R4W,
  // remaining Option+Ref2H2R1W, split closure/Iter2H3R1W, take counter/closure/
  // Iter3H3R2W, and size-hint Some1H1R1W. The returned parts are separate.
  // One active untoken/token builder and its old/new backing, Char String,
  // iterator/closure/index/Char, plus five concat/header alternatives16H3R4W.
  // The original create name Array/iterator3H2R1W uses shared Array storage.
  // Co-count all six create/nine read/one untoken Result sites16H16R16W
  // and four own typed Issue alternatives4H4W. Child outcomes belong to their
  // original owner; these caller carriers never multiply by input length.
  let local_controls = @shape.collection_construction_extent({
    records: 10L + 16L + 3L + 16L + 4L,
    record_references: 11L + 3L + 2L + 16L,
    record_words: 9L + 4L + 1L + 16L + 4L,
    reference_arrays: 1L,
    reference_items: 2L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  }).unwrap()
  let scratch = @shape.add_collection_construction_extents(
    parts,
    @shape.add_collection_construction_extents(local_controls, {
      record_headers: nfc.record_headers + utf8_h,
      reference_slots: nfc.reference_slots + utf8_r,
      scalar_words: nfc.scalar_words + utf8_w,
    }).unwrap(),
  ).unwrap()
  // Both decoded names together are <=U. On success the reconstructed text
  // equals the original input exactly, so its additional owned backing is U.
  // Reference1H3R plus its three String headers3H; no input-body copy charged.
  // On refusal, untoken raw/decoded and token/concat old/new strings/builders
  // fit <=10U+42: escape output<=2U, pinned buffer overlap<=3*output; the
  // three concat prefixes13+14+14 plus one initial buffer slot add42. This envelope
  // co-counts sequential alternatives beside NFC, not a minimum/live-heap claim.
  Some({
    retained: reference_read_retained_units,
    scratch,
    retained_utf16_units: 2L * u,
    scratch_utf16_units: nfc.owned_utf16_units + 10L * u + 42L,
  })
}

///|
let reference_read_retained_units : @shape.CollectionConstructionExtent = {
  record_headers: 4L,
  reference_slots: 3L,
  scalar_words: 0L,
}

///|
/// Fixed constructor controls of the quantity recipe itself, not the Reference
/// body it describes. NFC's record/Some/checked output3H1R8W; the UTF8 tuple
/// is installed immutable DATA and creates no per-call record. Collection
/// input1H9W plus the SAME shared expansion controls, one input sum record1H3W,
/// two checked expanded additions10H2R20W, and returned
/// inventory/Some2H3R3W. No input-sized backing is built by this quotation.
pub fn reference_read_inventory_quotation_extent() -> @shape.CollectionConstructionExtent {
  reference_read_inventory_quote_controls
}

///|
let reference_read_inventory_quote_controls : @shape.CollectionConstructionExtent = {
  let expansion = @shape.collection_construction_quotation_extent()
  {
    record_headers: expansion.record_headers + 17L,
    reference_slots: expansion.reference_slots + 6L,
    scalar_words: expansion.scalar_words + 43L,
  }
}
