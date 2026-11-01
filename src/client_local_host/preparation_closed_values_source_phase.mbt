///|
fn closed_values_units_subtract(
  left : @execution.PreparationRepresentationUnits,
  right : @execution.PreparationRepresentationUnits,
) -> @execution.PreparationRepresentationUnits? {
  if right.record_headers < 0L ||
    right.reference_slots < 0L ||
    right.scalar_words < 0L ||
    right.owned_utf16_units < 0L ||
    right.owned_wire_bytes < 0L ||
    left.record_headers < right.record_headers ||
    left.reference_slots < right.reference_slots ||
    left.scalar_words < right.scalar_words ||
    left.owned_utf16_units < right.owned_utf16_units ||
    left.owned_wire_bytes < right.owned_wire_bytes {
    return None
  }
  Some({
    record_headers: left.record_headers - right.record_headers,
    reference_slots: left.reference_slots - right.reference_slots,
    scalar_words: left.scalar_words - right.scalar_words,
    owned_utf16_units: left.owned_utf16_units - right.owned_utf16_units,
    owned_wire_bytes: left.owned_wire_bytes - right.owned_wire_bytes,
  })
}
