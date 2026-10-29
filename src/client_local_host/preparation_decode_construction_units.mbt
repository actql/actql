///|
/// Project domain-owned slots; only the shared tariff performs byte pricing.
fn decode_construction_preparation_units(
  units : @decode.AdmissionConstructionUnits,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: units.record_headers,
    reference_slots: units.reference_slots,
    scalar_words: units.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
