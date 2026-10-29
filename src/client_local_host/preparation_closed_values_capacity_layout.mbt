///|
/// Fixed record packet: charge each declared field as both reference and word
/// conservatively, rather than pretend a precise engine representation. The
/// small explicit slack is reported separately from observed logical charges.
fn closed_values_capacity_record_packet(
  count : Int64,
  fields : Int64,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: count,
    reference_slots: fields,
    scalar_words: fields,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
