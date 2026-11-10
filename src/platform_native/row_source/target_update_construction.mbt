///|
/// Same prepared provider and already retained changes, not a new limit or
/// permission. Zero selects the pre-response frame; the original observation
/// supplies the next size BEFORE Reader/buffer/document construction. Other
/// than closed Text projections retain their original maximum projection.
pub fn native_relation_file_target_update_construction(
  provider : NativeRelationFilePreparedProvider,
  writable_fields : Int,
  response_bytes : Int,
  changes_wire : String,
) -> (@execution.ExecutionCapacity, Int64)? {
  let limits = provider.limits
  let contract = @rows.relation_document_prepared_contract(
    provider.prepared_contract,
  )
  guard writable_fields > 0 &&
    writable_fields <= limits.page.max_nodes &&
    changes_wire.length() <= limits.page.max_bytes &&
    file_capture_response_backing_page(limits.page, Some(response_bytes))
    is Some(page) &&
    file_capture_projection_backing_page(
      contract,
      limits.page,
      Some(response_bytes),
    )
    is Some(projected) &&
    file_capture_provider_construction(
      provider.selection,
      limits,
      contract,
      prepared_contract=Some(provider.prepared_contract),
      response_bytes=Some(response_bytes),
      writable_fields~,
    )
    is Some((document, document_units)) else {
    return None
  }
  // The original String has not been encoded again merely to quote it. UTF8
  // needs at most three bytes per UTF16 unit; both original guards stay below.
  let encoded_change_bytes = 3L * changes_wire.length().to_int64()
  let change_bytes = Int64::min(
    limits.page.max_bytes.to_int64(),
    encoded_change_bytes,
  ).to_int()
  let change_bytes = Int::max(1, change_bytes)
  let change_nodes = Int::min(limits.page.max_nodes, change_bytes)
  let change_depth = Int::min(limits.page.max_depth, change_nodes)
  guard @local.installed_json_effect_response_construction_capacity(
      document, change_bytes, change_nodes, change_depth,
    )
    is Some(construction) &&
    @decode.preserving_json_admission_construction_inventory(
      change_bytes, change_nodes, change_depth,
    )
    is Some(request) &&
    @canonical.nfc_lf_construction_scratch_extent(change_bytes)
    is Some(normalizing) &&
    @canonical.nfc_lf_retained_output_units(change_bytes.to_int64())
    is Some(text) &&
    @execution.checked_preparation_add_product(128L, text, 6L) is Some(encoded) else {
    return None
  }
  let text_profile = file_capture_text_contract_nodes(contract) is Some(_)
  // Numeric/reference/nested Contracts retain their full original output
  // envelope. Only the existing closed Text law bounds rendering by text.
  let value_bytes = if text_profile {
    Int64::min(limits.page.max_bytes.to_int64(), encoded).to_int()
  } else {
    limits.page.max_bytes
  }
  let value_nodes = if text_profile {
    change_nodes
  } else {
    limits.page.max_nodes
  }
  let value_depth = if text_profile {
    change_depth
  } else {
    limits.page.max_depth
  }
  let output_bytes = Int64::min(
    limits.page.max_bytes.to_int64(),
    response_bytes.to_int64() + value_bytes.to_int64(),
  )
  guard file_capture_metadata_capacity(
      provider.selection,
      limits,
      prepared_provider=Some(provider),
    )
    is Some(controls) &&
    native_relation_target_observation_capacity(
      provider,
      writable_fields,
      page=Some(projected),
    )
    is Some(observation) &&
    @files.native_filesystem_write_layout() is Some(writer) &&
    @files.native_filesystem_read_layout() is Some(reader) &&
    @encode.text_writer_construction_inventory(
      projected.max_bytes,
      projected.max_nodes,
      projected.max_depth,
    )
    is Some(before) &&
    @encode.text_writer_construction_inventory(
      value_bytes, value_nodes, value_depth,
    )
    is Some(value_writer) &&
    @execution.compose_preparation_representation([
      document_units,
      {
        record_headers: request.record_headers,
        reference_slots: request.reference_slots,
        scalar_words: request.scalar_words,
        owned_utf16_units: request.owned_utf16_units,
        owned_wire_bytes: encoded_change_bytes,
      },
      {
        record_headers: normalizing.record_headers,
        reference_slots: normalizing.reference_slots,
        scalar_words: normalizing.scalar_words,
        owned_utf16_units: normalizing.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: before.record_headers,
        reference_slots: before.reference_slots,
        scalar_words: before.scalar_words,
        owned_utf16_units: before.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: value_writer.record_headers,
        reference_slots: value_writer.reference_slots,
        scalar_words: value_writer.scalar_words,
        owned_utf16_units: value_writer.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
      {
        record_headers: 8L,
        reference_slots: 16L,
        scalar_words: 8L,
        owned_utf16_units: text,
        owned_wire_bytes: page.max_bytes.to_int64() + output_bytes,
      },
    ])
    is Some(raw_units) else {
    return None
  }
  guard @execution.preparation_representation_cost({
      record_headers: value_writer.record_headers,
      reference_slots: value_writer.reference_slots,
      scalar_words: value_writer.scalar_words,
      owned_utf16_units: value_writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(emitter) else {
    return None
  }
  let names = 16L * provider.selection.name.length().to_int64() +
    8L * 64L +
    10L * 17L +
    8L
  let native = reader.root_payload_bytes +
    reader.reader_payload_bytes +
    reader.observation_payload_bytes +
    2L * reader.acquisition_payload_bytes +
    5L * reader.external_object_overhead_bytes +
    12L * provider.selection.directory.length().to_int64() +
    2L * (writer.writer_payload_bytes + writer.external_object_overhead_bytes) +
    names +
    16L * limits.diagnostic_ceiling.to_int64() +
    6L
  guard @execution.preparation_representation_cost({
      // Same generation/ACK/predecessor, plus callback/Result controls. The
      // complete changes buffer and replacement overlap remain held on error.
      record_headers: 12L,
      reference_slots: 32L,
      scalar_words: 16L,
      owned_utf16_units: 0L,
      owned_wire_bytes: output_bytes + encoded_change_bytes,
    })
    is Some(carriers) &&
    @execution.execution_capacity(
      controls + observation + native + carriers + emitter,
      controls + observation + native + carriers + emitter,
    )
    is Some(extra) &&
    @execution.add_execution_capacity(construction, extra) is Some(capacity) &&
    target_update_native_placement(raw_units, native) is Some(raw) else {
    return None
  }
  Some((capacity, raw))
}

///|
// Native conversion of actual constructor families, never logical tariff
// bytes or spare capacity. Sum simultaneous arrays/text to bound the largest
// individual allocation; retain doubling/terminator/header and fixed FS data.
fn target_update_native_placement(
  units : @execution.PreparationRepresentationUnits,
  native : Int64,
) -> Int64? {
  let (header, width, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  let text = units.owned_utf16_units
  guard text >= 0L &&
    text <= 2147483647L &&
    @execution.checked_preparation_add_product(
      units.reference_slots,
      units.scalar_words,
      1L,
    )
    is Some(slots) &&
    slots >= 0L &&
    @execution.checked_preparation_add_product(1L, slots, 2L) is Some(slots) &&
    @execution.checked_preparation_add_product(array_header, slots, pointer)
    is Some(array) &&
    @execution.checked_preparation_add_product(
      array_header,
      units.owned_wire_bytes,
      1L,
    )
    is Some(bytes) else {
    return None
  }
  let mut backing = 1L
  while backing < text {
    backing *= 2L
  }
  guard @execution.checked_preparation_add_product(header, backing + 1L, width)
    is Some(string) else {
    return None
  }
  Some(Int64::max(native, Int64::max(string, Int64::max(array, bytes))))
}
