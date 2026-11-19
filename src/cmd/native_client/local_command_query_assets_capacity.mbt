///|
// Additional Runtime-owned Query asset construction on the SAME initial
// Read. The closed manifest already bounds each of the two optional members
// by 65536 bytes. This is a simultaneous constructor quote, not new policy,
// a spare-bootstrap assertion, or a physical retirement acknowledgement.
fn local_command_query_assets_capacity(
  diagnostic_ceiling : Int,
) -> (Int64, Int64)? {
  if diagnostic_ceiling <= 0 {
    return None
  }
  guard @local_filesystem.native_filesystem_read_layout() is Some(layout) &&
    layout.reader_payload_bytes > 0L &&
    layout.observation_payload_bytes > 0L &&
    layout.external_object_overhead_bytes > 0L &&
    layout.reader_payload_bytes <= 2305843009213693951L &&
    layout.observation_payload_bytes <= 2305843009213693951L &&
    layout.external_object_overhead_bytes <= 2305843009213693951L &&
    local_project_text_payload_extent(65536L) is Some((text_r, text_e)) &&
    @shape.map_construction_extent(1L, 8L) is Some(map) &&
    // One manifest plus at most eight licenses/libraries/assets. Charge the
    // complete witness backing during relocation, not just two new slots.
    @execution.preparation_array_representation(1L, 25L, true)
    is Some(witnesses) &&
    @execution.preparation_representation_cost(witnesses) is Some(witnesses) &&
    @execution.preparation_representation_cost({
      record_headers: map.record_headers,
      reference_slots: map.reference_slots,
      scalar_words: map.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(map) &&
    @execution.preparation_representation_cost({
      // Runtime fieldR1; original Some(tuple)H2/R3/W1. No CLI copy remains.
      // Each observed file recordH1/R3 retains its original name and stat;
      // the two immutable decoded bodies are in text_r exactly once.
      record_headers: 2L + 2L,
      reference_slots: 1L + 3L + 6L,
      scalar_words: 1L,
      owned_utf16_units: 37L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.preparation_array_representation(6L, 272L, true)
    is Some(hash_arrays) &&
    @execution.preparation_representation_cost(hash_arrays) is Some(hash_arrays) &&
    @execution.preparation_representation_cost({
      // Two original incremental hashers: recordR3/W3, state8/words64/block64
      // arrays above; two returned 64-unit digest strings. They are compared,
      // not retained as extra Runtime assets or execution permissions.
      record_headers: 2L + 2L,
      reference_slots: 6L,
      scalar_words: 6L,
      owned_utf16_units: 128L,
      owned_wire_bytes: 0L,
    })
    is Some(hashes) &&
    @execution.preparation_array_representation(6L, 12L, true) is Some(paths) &&
    @execution.preparation_representation_cost(paths) is Some(paths) else {
    return None
  }
  // No allocator reuse is assumed between the two read constructors. Their
  // UTF8/Bytes/FixedArray overlap uses the existing text intake recipe. The
  // borrowed data Root is unchanged; the extra original observations and
  // Reader payloads use the SAME compiled filesystem's readonly sizeof facts.
  guard native_storage_sum([
      controls,
      witnesses,
      2L * text_r,
      2L * layout.observation_payload_bytes,
      2L * layout.external_object_overhead_bytes,
    ])
    is Ok(retained) &&
    native_storage_sum([
      controls,
      witnesses,
      map,
      hash_arrays,
      hashes,
      paths,
      2L * text_e,
      2L * layout.observation_payload_bytes,
      2L * layout.reader_payload_bytes,
      4L * layout.external_object_overhead_bytes,
      // Two fixed canonical names: query.json10, query-evidence.json19.
      // UTF8/C name copies8 per unit plus terminators; original diagnostics
      // retain replacement/returned-byte overlap at their existing bound.
      8L * 29L + 4L,
      12L * diagnostic_ceiling.to_int64() + 12L,
    ])
    is Ok(execution) else {
    return None
  }
  Some((retained, execution))
}
