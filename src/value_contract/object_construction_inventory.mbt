///|
/// Already admitted child contracts are borrowed. Only this original field
/// assembler's returned fields and its own sequential name/sort work are new.
pub(all) struct ObjectConstructionInventory {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn object_construction_inventory(
  fields : Int,
  max_name_utf16_units : Int,
) -> ObjectConstructionInventory? {
  if fields < 0 || max_name_utf16_units < 0 {
    return None
  }
  let f = fields.to_int64()
  let held = object_retained_construction_extent(fields, 1).unwrap()
  // Same pinned in-place sort family as admission: <=6F/4F/10F controls.
  // Remaining fixed20/16/14 covers scalar/name outcomes and typed return;
  // one seen-Map lives beside the fields. NFC runs one original name at a time.
  let frame = @shape.collection_construction_extent({
    records: 20L + 6L * f,
    record_references: 16L + 4L * f,
    record_words: 14L + 10L * f,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 1L,
    map_entries: f,
  }).unwrap()
  let nfc = @canonical.nfc_lf_construction_extent(max_name_utf16_units).unwrap()
  Some({
    retained: held,
    scratch: @shape.add_collection_construction_extents(frame, {
      record_headers: nfc.record_headers,
      reference_slots: nfc.reference_slots,
      scalar_words: nfc.scalar_words,
    }).unwrap(),
    scratch_utf16_units: nfc.owned_utf16_units,
  })
}

///|
pub fn object_retained_construction_extent(
  fields : Int,
  instances : Int,
) -> @shape.CollectionConstructionExtent? {
  if fields < 0 || instances < 0 {
    return None
  }
  let f = fields.to_int64()
  let i = instances.to_int64()
  // Contract nullable, Object payload tag and Fields name_bytes are three
  // independent scalar words; child bodies remain borrowed.
  @shape.collection_construction_extent({
    records: 3L * i + f,
    record_references: 3L * i + 2L * f,
    record_words: 3L * i,
    reference_arrays: i,
    reference_items: f,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: 0L,
    map_entries: 0L,
  })
}
