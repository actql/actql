// Fixed prefix from genuine722877b5, with only the original additive row
// composition retained as the paired oracle. The previous0385 fixture also
// contained an already-replaced fixed parser peak, so it could not isolate
// row workspace or marker-history changes. No production parser is copied.

///|
fn original_capture_profile_before_row_workspace(
  metadata : @catalog.RangeConstructionMetadata,
  capture_bytes : Int,
  capture_nodes : Int,
  capture_depth : Int,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  recovery_bytes : Int,
  recovery_nodes : Int,
  recovery_depth : Int,
  clear : Bool,
) -> Array[@execution.ExecutionCapacity]? {
  if capture_bytes < 1 ||
    capture_nodes < 1 ||
    capture_depth < 1 ||
    recovery_bytes < 1 ||
    recovery_nodes < 1 ||
    recovery_depth < 1 {
    return None
  }
  // Saved recovery serializes complete original Preview/description input,
  // with an additional JSON String layer around native recovery wires. It
  // remains constructor material, separate from C's plaintext/Store custody.
  let wire = 7L * capture_bytes.to_int64() +
    metadata.schema_bytes +
    6L * metadata.target_units.to_int64() +
    1024L
  let nodes = capture_nodes.to_int64() + 4L * metadata.columns.to_int64() + 32L
  if wire > 2147483647L || nodes > 2147483647L {
    return None
  }
  // These are the SAME explicit limits supplied to recover_*_range_requests.
  // The binding's byte limit belongs to outgoing request construction; it
  // does not cap the independent incoming effects/recovery forests.
  let b = Int::min(wire.to_int(), recovery_bytes)
  let n = Int::min(nodes.to_int(), recovery_nodes)
  let binding_bytes = Int::min(wire.to_int(), metadata.limits.max_bytes)
  let (_, entry_bytes) = sheets_range_capture_normalization_inputs(
    binding_bytes, b, clear,
  )
  guard sheets_range_recovery_metadata_text_units(metadata)
    is Some(metadata_text_units) else {
    return None
  }
  let fresh_normalization_bytes = Int64::min(
    binding_bytes.to_int64(),
    metadata_text_units,
  ).to_int()
  let cold_normalization_bytes = Int64::min(
    entry_bytes.to_int64(),
    metadata_text_units,
  ).to_int()
  let entry_nodes = Int::min(n, entry_bytes)
  // Fresh metadata has no Preview values: columns, fixed coordinates, the
  // immutable target and (clear only) the already bounded marker vector.
  // A target JSON node consumes at least one original encoded byte. Its
  // UTF8 input is <=3*the retained original UTF16 units. No new input cap.
  let metadata_nodes = 4L * metadata.columns.to_int64() +
    3L * metadata.target_units.to_int64() +
    64L
  if metadata_nodes > 2147483643L {
    return None
  }
  let metadata_nodes = metadata_nodes.to_int()
  let zero : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard sheets_range_parsed_construction(b, n, recovery_depth) is Some(input) &&
    sheets_range_json_inventory(b, n) is Some(native_build) &&
    sheets_range_json_retained_inventory(b, n) is Some(native) &&
    sheets_range_native_parse_text(b, n, recovery_depth) is Some(native_text) &&
    (if clear {
      sheets_range_parsed_construction(entry_bytes, entry_nodes, recovery_depth)
    } else {
      Some(zero)
    })
    is Some(entry_input) &&
    (if clear {
      sheets_range_json_inventory(entry_bytes, entry_nodes)
    } else {
      Some(zero)
    })
    is Some(entry_build) &&
    (if clear {
      sheets_range_json_retained_inventory(entry_bytes, entry_nodes)
    } else {
      Some(zero)
    })
    is Some(entry) &&
    (if clear {
      sheets_range_native_parse_text(entry_bytes, entry_nodes, recovery_depth)
    } else {
      Some(zero)
    })
    is Some(entry_text) &&
    sheets_writer_units(recovery_bytes, metadata_nodes + 4, recovery_depth)
    is Some(writer) &&
    sheets_range_normalization_construction(cold_normalization_bytes)
    is Some(normalization) &&
    @canonical.nfc_lf_construction_extent(cold_normalization_bytes)
    is Some(normalized_text) &&
    sheets_range_parsed_construction(
      binding_bytes,
      metadata_nodes,
      metadata.limits.max_depth,
    )
    is Some(metadata_input) &&
    sheets_range_json_inventory(binding_bytes, metadata_nodes)
    is Some(metadata_native) &&
    sheets_range_canonical_construction(
      metadata_nodes,
      metadata.limits.max_depth,
    )
    is Some(metadata_canonical) &&
    sheets_writer_units(
      binding_bytes,
      metadata_nodes + 4,
      metadata.limits.max_depth,
    )
    is Some(metadata_writer) &&
    sheets_range_normalization_construction(fresh_normalization_bytes)
    is Some(metadata_normalization) &&
    @canonical.nfc_lf_construction_extent(fresh_normalization_bytes)
    is Some(metadata_text) &&
    @shape.collection_construction_extent({
      // Entry object/Strings and return holder; Native+Host outer/inner
      // request arrays and currents survive only through actual retirement.
      records: 5L,
      record_references: 5L,
      record_words: 0L,
      reference_arrays: 5L,
      reference_items: 5L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(output) &&
    @execution.compose_preparation_representation([
      sheets_collection_units(output),
      { ..zero, owned_utf16_units: binding_bytes.to_int64() + 128L, },
    ])
    is Some(retained) else {
    return None
  }
  // JSON.stringify's two original input Strings/encodings are caller-owned
  // construction, including the pre-byte-refusal path. They are not retained
  // Native output. Keep the original complete escaped-wire bound here.
  let inputs = {
    ..zero,
    record_headers: 6L,
    owned_utf16_units: 2L * wire,
    owned_wire_bytes: 2L * wire,
  }
  // Both paths normalize only reconstructed original-binding metadata after
  // canonical equality. Clear alone parses the supplied marker document first;
  // range compares its entire wire directly without another supplied tree.
  let normalized = { ..metadata_native, owned_utf16_units: 0L, }
  let metadata_normalized = { ..metadata_native, owned_utf16_units: 0L, }
  // The first range_parse has returned before the second starts. The
  // completed first native tree survives; the second Source check and native
  // constructor are sequential. Both input Strings/encodings and every
  // complete failed-prefix constructor keep their original bounds.
  guard @execution.compose_preparation_representation([inputs, input, native])
    is Some(parse_peak) &&
    @execution.compose_preparation_representation([
      inputs, native, native_build, native_text,
    ])
    is Some(native_parse_peak) &&
    @execution.compose_preparation_representation([
      inputs, native, native, entry_input,
    ])
    is Some(entry_peak) &&
    @execution.compose_preparation_representation([
      inputs, native, native, entry_build, entry_text,
    ])
    is Some(entry_native_peak) &&
    @execution.compose_preparation_representation([
      inputs, native, native, entry, metadata_native, normalized, normalization,
    ])
    is Some(normalize_peak) &&
    @execution.compose_preparation_representation([
      inputs,
      native,
      native,
      entry,
      metadata_native,
      normalized,
      metadata_canonical,
      writer,
      { ..zero, owned_utf16_units: normalized_text.max_output_utf16_units, },
    ])
    is Some(canonical_peak) &&
    @execution.compose_preparation_representation([
      inputs, native, native, entry, metadata_input, metadata_native,
    ])
    is Some(expected_peak) &&
    @execution.compose_preparation_representation([
      inputs, metadata_input, metadata_native,
    ])
    is Some(metadata_parse_peak) &&
    @execution.compose_preparation_representation([
      inputs, metadata_native, metadata_normalized, metadata_normalization,
    ])
    is Some(metadata_normalize_peak) &&
    @execution.compose_preparation_representation([
      inputs,
      metadata_native,
      metadata_normalized,
      metadata_canonical,
      metadata_writer,
      { ..zero, owned_utf16_units: metadata_text.max_output_utf16_units, },
    ])
    is Some(metadata_canonical_peak) &&
    sheets_range_capture_phase_capacity(retained, [
      parse_peak, native_parse_peak, entry_peak, entry_native_peak, normalize_peak,
      canonical_peak, expected_peak, metadata_parse_peak, metadata_normalize_peak,
      metadata_canonical_peak,
    ])
    is Some(fixed) &&
    sheets_range_request_capacity(
      metadata, input_bytes, input_nodes, input_depth, clear,
    )
    is Some(row) &&
    @shape.collection_construction_extent({
      records: 0L,
      record_references: 0L,
      record_words: 0L,
      reference_arrays: 0L,
      reference_items: 4L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(row_slots) &&
    sheets_constructor_capacity([sheets_collection_units(row_slots)])
    is Some(row_slots) &&
    @execution.add_execution_capacity(row, row_slots) is Some(row) else {
    return None
  }
  let row = if clear {
    guard sheets_clear_recovery_marker_capacity(metadata.limits.max_depth)
      is Some(marker) &&
      @execution.add_execution_capacity(row, marker) is Some(combined) else {
      return None
    }
    combined
  } else {
    row
  }
  guard sheets_range_effect_id_capacity() is Some(effect_id) else {
    return None
  }
  Some([fixed, row, effect_id])
}

///|
test "range recovery retains all row results without repeating covered private workspace" {
  let metadata = recovery_guard_test_metadata(300000)
  let old = original_capture_profile_before_row_workspace(
    metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, false,
  ).unwrap()
  let selected = sheets_range_capture_profile(
    metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, false,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(old[1]) >
    @execution.execution_capacity_retained_bytes(old[1]),
  )
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected[1]),
    @execution.execution_capacity_retained_bytes(old[1]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[1]),
    @execution.execution_capacity_retained_bytes(selected[1]),
  )
  // The full fixed peak/failed prefix and zero-row demand stay unchanged.
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected[0]),
    @execution.execution_capacity_retained_bytes(old[0]),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[0]),
    @execution.execution_capacity_execution_bytes(old[0]),
  )
  for rows in [0, 1, 3] {
    let row_r = @execution.execution_capacity_retained_bytes(selected[1])
    let row_e = @execution.execution_capacity_execution_bytes(selected[1])
    assert_eq(
      row_r * rows.to_int64(),
      @execution.execution_capacity_retained_bytes(old[1]) * rows.to_int64(),
    )
    assert_true(
      row_e * rows.to_int64() <=
      @execution.execution_capacity_execution_bytes(old[1]) * rows.to_int64(),
    )
  }
}

///|
test "clear recovery retains the whole old marker envelope before sharing covered row workspace" {
  let metadata = recovery_guard_test_metadata(300000)
  let before = original_capture_profile_before_row_workspace(
    metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, true,
  ).unwrap()
  let selected = sheets_range_capture_profile(
    metadata, 1000000, 100000, 64, 100000, 10000, 16, 2000000, 200000, 32, true,
  ).unwrap()
  assert_eq(selected.length(), before.length())
  for index in [0, 2] {
    assert_eq(
      @execution.execution_capacity_retained_bytes(selected[index]),
      @execution.execution_capacity_retained_bytes(before[index]),
    )
    assert_eq(
      @execution.execution_capacity_execution_bytes(selected[index]),
      @execution.execution_capacity_execution_bytes(before[index]),
    )
  }
  let marker = sheets_clear_recovery_marker_capacity(metadata.limits.max_depth).unwrap()
  let history = @execution.execution_capacity_execution_bytes(marker)
  assert_eq(@execution.execution_capacity_retained_bytes(marker), 0L)
  for rows in [0L, 1L, 3L] {
    assert_eq(
      rows * @execution.execution_capacity_retained_bytes(selected[1]),
      rows * (@execution.execution_capacity_retained_bytes(before[1]) + history),
    )
  }
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected[1]),
    @execution.execution_capacity_retained_bytes(selected[1]),
  )
}

///|
test "uncovered or overflowing range row phase preserves its original quantity" {
  let prefix : @execution.PreparationRepresentationUnits = {
    record_headers: 1L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let row = @execution.execution_capacity(7L, 29L).unwrap()
  let small = @execution.execution_capacity(0L, 1L).unwrap()
  assert_true(
    physical_equal(sheets_range_cofund_recovery_row(small, prefix, row), row),
  )
  let maximum = @execution.execution_capacity(
    9223372036854775807L, 9223372036854775807L,
  ).unwrap()
  assert_true(
    physical_equal(sheets_range_cofund_recovery_row(maximum, prefix, row), row),
  )
  let invalid = { ..prefix, owned_wire_bytes: -1L, }
  assert_true(
    physical_equal(sheets_range_cofund_recovery_row(small, invalid, row), row),
  )
}
