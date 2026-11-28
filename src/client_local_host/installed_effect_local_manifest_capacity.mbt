///|
// The same checked Manifest visits its Result names and Effect table headers,
// builds temporary maps and name arrays, and adopts a private Artifact vector.
pub fn installed_effect_local_manifest_inventory(
  results : Int,
  headers : Int,
  artifacts : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @execution.ExecutionCapacity? {
  let slots = results.to_int64() + headers.to_int64() + artifacts.to_int64()
  guard results >= 0 &&
    headers >= 0 &&
    artifacts >= 0 &&
    max_nodes > 0 &&
    max_nodes < 2147483647 &&
    @shape.collection_construction_extent({
      records: 12L + 2L * slots,
      record_references: 26L + 2L * slots,
      record_words: 14L + slots,
      reference_arrays: 4L,
      reference_items: 4L * slots,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 3L,
      map_entries: headers.to_int64() + artifacts.to_int64(),
    })
    is Some(collections) &&
    @encode.measuring_writer_construction_extent(
      Int64::min(max_nodes.to_int64() + 1L, slots + 6L).to_int(),
      max_depth,
    )
    is Some(writer) &&
    @execution.preparation_array_representation(1L, artifacts.to_int64(), false)
    is Some(retained) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace: {
      record_headers: collections.record_headers + writer.record_headers,
      reference_slots: collections.reference_slots + writer.reference_slots,
      scalar_words: collections.scalar_words + writer.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
