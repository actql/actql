///|
// Each admitted Source observation has exactly six Catalog references. These
// original selected slots fund the existing tuple/key/seen collection, not the
// whole Environment or a count-sized lookup index. One cursor is active.
fn effect_unit_catalog_selection_capacity(
  parts : Int,
) -> @execution.ExecutionCapacity? {
  if parts < 0 {
    return None
  }
  let n = parts.to_int64() * 6L
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 16L + 2L * n,
      reference_slots: 32L + 6L * n,
      scalar_words: 24L + 4L * n,
      // Closed role vocabulary plus fixed SHA256 spelling and delimiter.
      owned_utf16_units: 192L * n,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 8L,
      reference_slots: 16L,
      scalar_words: 20L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}
