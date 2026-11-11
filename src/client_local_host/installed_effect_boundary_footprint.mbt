///|
/// Private constructor quantity for one fixed opaque boundary: three borrowed
/// scalar text fields, canonical key/value fragments, complete UTF8 hash input,
/// SHA256 digest/CID and the frozen three-field result. It is not a footprint,
/// provider binding, grant or currentness proof. Original text stays borrowed;
/// the same Plan's full control retention owns every returned result.
pub fn installed_effect_opaque_boundary_footprint_capacity(
  origin : String,
  account : String,
  object_units : Int,
) -> @execution.ExecutionCapacity? {
  if origin.is_empty() || account.is_empty() || object_units < 1 {
    return None
  }
  let text_units = origin.length().to_int64() +
    account.length().to_int64() +
    object_units.to_int64()
  // Fixed three ASCII keys/wrappers fit96 units. A JSON escape needs at most
  // six UTF16 units per input unit; no value normalization or second parse.
  guard @execution.checked_preparation_add_product(96L, text_units, 6L)
    is Some(wire) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) &&
    @shape.collection_construction_extent({
      records: 48L,
      record_references: 128L,
      record_words: 32L,
      reference_arrays: 16L,
      reference_items: 64L,
      scalar_arrays: 2L,
      scalar_items: 16L,
      maps: 2L,
      map_entries: 6L,
    })
    is Some(controls) &&
    @execution.preparation_representation_cost({
      record_headers: controls.record_headers + hash.record_headers,
      reference_slots: controls.reference_slots + hash.reference_slots,
      scalar_words: controls.scalar_words + hash.scalar_words,
      // Quoted values, key/value fragments, join/wrapper and flattening may
      // coexist. Digest64 and CID71 remain covered during their construction.
      owned_utf16_units: 6L * wire + 256L + hash.owned_utf16_units,
      // Complete UTF8 conversion/copy and fixed native hash/context backing.
      owned_wire_bytes: 8L * wire + 1024L + hash.owned_wire_bytes,
    })
    is Some(workspace) else {
    return None
  }
  @execution.execution_capacity(0L, workspace)
}
