///|
// One original saved observation: envelope + BOTH full child constructors +
// bounded extent measurement. This is an optional same-Root reservation, not
// another profile, policy allowance or Native/physical allocation statement.
fn journal_observation_construction_capacity() -> (Int64, Int64)? {
  let bytes = 131072
  guard @publication.run_evidence_admission_construction_inventory(
      bytes, 8192, 64,
    )
    is Some(child) &&
    @decode.preserving_json_admission_construction_inventory(bytes, 8, 2)
    is Some(envelope) &&
    @encode.text_writer_construction_inventory(bytes, 8, 1) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: child.record_headers,
      reference_slots: child.reference_slots,
      scalar_words: child.scalar_words,
      owned_utf16_units: child.owned_utf16_units,
      owned_wire_bytes: child.owned_wire_bytes,
    })
    is Some(child_peak) &&
    @execution.preparation_representation_cost({
      record_headers: envelope.record_headers + writer.record_headers,
      reference_slots: envelope.reference_slots + writer.reference_slots,
      scalar_words: envelope.scalar_words + writer.scalar_words,
      owned_utf16_units: envelope.owned_utf16_units + writer.owned_utf16_units,
      owned_wire_bytes: bytes.to_int64(),
    })
    is Some(envelope_peak) &&
    @execution.preparation_representation_cost({
      // Original keyed extent walk, TWO evidence outputs still held:
      // F=4*(64+1)+4*(0 contracts+2 evidence+1)=272.
      record_headers: 284L,
      reference_slots: 1112L,
      scalar_words: 1104L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(measurement) &&
    @execution.preparation_representation_cost({
      // Envelope expected-key Array construction3H/19R/2W; twelve
      // parse/admit/lookup/text/error/returned Result/Option carriers12H/12R/12W;
      // original paired metadata1H/2R. This already covers those outputs.
      // Resident Some1H/1R/1W, capture closure+Some2H/2R/1W,
      // and original resize/quote Some+tuple/control3H/3R/5W.
      // Cell's additional reference slot is in its ordinary row quote.
      record_headers: 22L,
      reference_slots: 39L,
      scalar_words: 21L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.preparation_representation_cost({
      record_headers: child.retained.record_headers,
      reference_slots: child.retained.reference_slots,
      scalar_words: child.retained.scalar_words,
      owned_utf16_units: child.retained_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(child_retention) &&
    @execution.preparation_representation_cost({
      // Escaping paired metadata and the cell's Some; its new reference
      // slot is separately present even on the ordinary outer-only path.
      record_headers: 2L,
      reference_slots: 3L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(retained_controls) &&
    @execution.checked_preparation_add_product(
      retained_controls, child_retention, 2L,
    )
    is Some(retention) &&
    @execution.checked_preparation_add_product(envelope_peak, child_peak, 2L)
    is Some(total) &&
    @execution.checked_preparation_add_product(total, measurement, 1L)
    is Some(total) &&
    @execution.checked_preparation_add_product(total, controls, 1L)
    is Some(total) else {
    return None
  }
  Some((retention, total))
}

///|
fn journal_observation_evidence_retention(
  original : @publication.RunEvidenceValue,
) -> Int64? {
  guard @publication.run_evidence_value_representation_extent(
      original, 8192, 64, 2147483647,
    )
    is Ok(extent) else {
    return None
  }
  @execution.canonical_preparation_retained_bytes(
    extent.canonical,
    3L * extent.contract_records + extent.contract_strings,
    7L * extent.contract_records,
    5L * extent.contract_records,
    extent.contract_text_utf16_units,
  )
}

///|
// Called only while the preconstructor reservation covers both outputs and
// their extent walk. Canonical arrays use ACTUAL backing, including spare slots.
fn journal_observation_retention(
  original : @host.ClientRunObservationOriginals,
) -> Int64? {
  guard journal_observation_evidence_retention(original.prepared())
    is Some(prepared) &&
    journal_observation_evidence_retention(original.authorization())
    is Some(authorization) &&
    @execution.preparation_representation_cost({
      // Existing ClientRunObservationOriginals1H/2R + resident Some1H/1R/1W.
      // Each evidence's H6/R7/W5 includes its own wire_usage Some/tuple.
      record_headers: 2L,
      reference_slots: 3L,
      scalar_words: 1L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.checked_preparation_add_product(prepared, authorization, 1L)
    is Some(total) &&
    @execution.checked_preparation_add_product(total, controls, 1L)
    is Some(total) else {
    return None
  }
  Some(total)
}
