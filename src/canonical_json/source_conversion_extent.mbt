///|
/// Logical constructor quantities for from_source's existing immutable tree.
/// Inputs are independent bounds for ONE current document. They are neither
/// observations of an accepted tree, byte prices, authority nor a reservation.
pub(all) struct SourceConversionConstructionExtent {
  retained : @shape.CollectionConstructionExtent
  scratch : @shape.CollectionConstructionExtent
  retained_utf16_units : Int64
  scratch_utf16_units : Int64
} derive(Eq, Debug)

///|
pub fn source_conversion_construction_extent(
  nodes : Int,
  fields : Int,
  objects : Int,
  arrays : Int,
  depth : Int,
  input_text_units : Int,
) -> SourceConversionConstructionExtent? {
  if nodes < 1 ||
    fields < 0 ||
    objects < 0 ||
    arrays < 0 ||
    depth < 0 ||
    fields > nodes ||
    objects > nodes ||
    arrays > nodes ||
    input_text_units < 0 {
    return None
  }
  let n = nodes.to_int64()
  let f = fields.to_int64()
  let o = objects.to_int64()
  let a = arrays.to_int64()
  guard @shape.collection_construction_extent({
      // CanonicalValue variant per node; FrozenArray wrapper per container;
      // object (key,value) tuple and separately normalized key String per field.
      records: n + o + a + 2L * f,
      record_references: n + o + a + 2L * f,
      record_words: n,
      reference_arrays: o + a,
      reference_items: n + f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(retained) &&
    @shape.collection_construction_extent({
      // Original InputBudget, map callback closure and seen Map per object.
      // The complete map inventory and Array growth overlap coexist with the
      // retained canonical tree. VM call frames are outside this source recipe.
      records: 1L + o + a,
      record_references: o + a,
      record_words: 3L,
      reference_arrays: o + a,
      reference_items: n + f,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: o,
      map_entries: f,
    })
    is Some(scratch) &&
    @value.nfc_lf_construction_scratch_extent(input_text_units) is Some(nfc) &&
    @value.nfc_lf_retained_output_units(input_text_units.to_int64())
    is Some(text) &&
    @shape.add_collection_construction_extents(scratch, {
      record_headers: nfc.record_headers,
      reference_slots: nfc.reference_slots,
      scalar_words: nfc.scalar_words,
    })
    is Some(scratch) else {
    return None
  }
  Some({
    retained,
    scratch,
    retained_utf16_units: text,
    scratch_utf16_units: nfc.owned_utf16_units,
  })
}
