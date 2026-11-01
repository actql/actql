///|
// Native Json trees, their canonical projection and the original indexed
// Source are distinct constructors. Reuse the shared representation units;
// no byte tariff, Resource, admission or physical authority is defined here.
fn sheets_range_json_inventory(
  bytes : Int,
  nodes : Int,
) -> @execution.PreparationRepresentationUnits? {
  if bytes < 0 || nodes < 0 {
    return None
  }
  let n = nodes.to_int64()
  guard @shape.collection_construction_extent({
      records: n,
      record_references: n,
      record_words: n,
      reference_arrays: n,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: n,
      map_entries: n,
    })
    is Some(shape) else {
    return None
  }
  Some({
    record_headers: shape.record_headers,
    reference_slots: shape.reference_slots,
    scalar_words: shape.scalar_words,
    owned_utf16_units: bytes.to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
// The Source keeps this original binding beyond every individual Run. Back
// the reference, configuration String/bytes, native parse/canonical copies,
// checked Column vector and the actual retained binding before construction.
#export_name("sheetsRangeInstallationConstructionCapacity")
pub fn sheets_range_installation_construction_capacity(
  configuration_bytes : Int,
  columns : Int,
  origin_bytes : Int,
  spreadsheet_bytes : Int,
) -> @execution.ExecutionCapacity? {
  if configuration_bytes < 1 || columns < 1 || columns > 64 {
    return None
  }
  guard sheets_range_reference_construction_capacity(
      origin_bytes, spreadsheet_bytes,
    )
    is Some(reference) &&
    @catalog.range_reference_construction_bounds(
      origin_bytes, spreadsheet_bytes,
    )
    is Some(target) &&
    sheets_decoded_construction(configuration_bytes, 10 + 4 * columns, 32)
    is Some(configuration) &&
    sheets_decoded_construction(
      target.reference_bytes,
      target.reference_nodes,
      32,
    )
    is Some(target_input) &&
    sheets_range_json_inventory(configuration_bytes, 10 + 4 * columns)
    is Some(configuration_json) &&
    sheets_range_json_inventory(target.reference_bytes, target.reference_nodes)
    is Some(target_json) &&
    sheets_writer_units(target.reference_bytes, target.reference_nodes, 32)
    is Some(writer) &&
    @shape.collection_construction_extent({
      records: columns.to_int64() + 2L,
      record_references: columns.to_int64() + 10L,
      record_words: 2L * columns.to_int64() + 4L,
      reference_arrays: 1L,
      reference_items: columns.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(binding) &&
    sheets_constructor_capacity([
      configuration,
      configuration_json,
      target_input,
      target_json,
      target_json,
      writer,
      sheets_collection_units(binding),
      {
        record_headers: 4L,
        reference_slots: 6L,
        scalar_words: 0L,
        owned_utf16_units: configuration_bytes.to_int64() +
        2L * target.reference_bytes.to_int64(),
        owned_wire_bytes: configuration_bytes.to_int64() +
        target.reference_bytes.to_int64(),
      },
    ])
    is Some(bound) else {
    return None
  }
  @execution.add_execution_capacity(reference, bound)
}

///|
fn sheets_range_request_capacity(
  metadata : @catalog.RangeConstructionMetadata,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  clear : Bool,
) -> @execution.ExecutionCapacity? {
  if input_bytes < 1 ||
    input_nodes < 1 ||
    input_depth < 1 ||
    metadata.columns < 1 ||
    metadata.columns > 64 ||
    metadata.rows < 0 {
    return None
  }
  let b = Int::min(input_bytes, metadata.limits.max_bytes)
  let n = Int::min(input_nodes, metadata.limits.max_nodes)
  let d = Int::min(input_depth, metadata.limits.max_depth)
  guard @catalog.range_write_construction_bounds(metadata, b, clear)
    is Some(output) else {
    return None
  }
  let target_bytes = Int64::max(
    3L * metadata.target_units.to_int64(),
    input_bytes.to_int64(),
  )
  // Fixed request/failure envelope syntax, two decimal coordinates and the
  // request CID fit within1024 ASCII units; original variable text remains
  // separate below. This is a constructor bound, not a new input limit.
  let facts_bytes = 6L *
    (
      b.to_int64() +
      metadata.target_units.to_int64() +
      metadata.origin_units.to_int64() +
      metadata.spreadsheet_units.to_int64()
    ) +
    1024L
  let facts_nodes = n.to_int64() + metadata.target_units.to_int64() + 16L
  if target_bytes > 2147483647L ||
    facts_bytes > 2147483647L ||
    facts_nodes > 2147483647L {
    return None
  }
  guard sheets_decoded_construction(b, n, d) is Some(input) &&
    sheets_decoded_construction(
      Int::min(target_bytes.to_int(), metadata.limits.max_bytes),
      Int::min(n, metadata.limits.max_nodes),
      metadata.limits.max_depth,
    )
    is Some(target) &&
    sheets_decoded_construction(
      Int::min(output.body_bytes, metadata.limits.max_bytes),
      Int::min(output.body_nodes, metadata.limits.max_nodes),
      output.body_depth,
    )
    is Some(validation) &&
    sheets_range_json_inventory(b, n) is Some(native_input) &&
    sheets_range_json_inventory(facts_bytes.to_int(), facts_nodes.to_int())
    is Some(native_output) &&
    sheets_writer_units(output.body_bytes, output.body_nodes, output.body_depth)
    is Some(body_writer) &&
    sheets_writer_units(
      facts_bytes.to_int(),
      facts_nodes.to_int(),
      metadata.limits.max_depth,
    )
    is Some(facts_writer) else {
    return None
  }
  sheets_constructor_capacity([
    // Original value, selector and facts can overlap through projection. The
    // original target fast path still keeps the full changed-input refusal.
    input,
    input,
    target,
    target,
    validation,
    native_input,
    native_input,
    native_output,
    native_output,
    {
      // Payload/target facts use range_canonical(data_keys=true), preserving
      // original keys and values. Request identity hashes the framed original
      // UTF8 parts. Neither path invokes range_configuration_value or NFC;
      // installation/recovery configuration identity has its separate quote.
      record_headers: 3L,
      reference_slots: 14L,
      scalar_words: 4L,
      owned_utf16_units: 2L * input_bytes.to_int64() +
      target_bytes +
      facts_bytes +
      output.body_bytes.to_int64(),
      // Value/selector UTF8 inputs, both pre-refusal outgoing encodings and
      // original request-identity preimages remain independently bounded.
      owned_wire_bytes: 2L * input_bytes.to_int64() +
      target_bytes +
      3L * output.body_bytes.to_int64() +
      metadata.origin_units.to_int64() * 3L +
      128L,
    },
    body_writer,
    facts_writer,
    facts_writer,
  ])
}

///|
fn sheets_range_response_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  if bytes < 1 || nodes < 1 || depth < 1 || depth == 2147483647 {
    return None
  }
  guard sheets_decoded_construction(bytes, nodes, depth) is Some(input) &&
    sheets_target_projection_construction(nodes, depth) is Some(projection) &&
    sheets_writer_units(64, 3, 1) is Some(writer) else {
    return None
  }
  sheets_constructor_capacity([input, projection, writer])
}

///|
fn sheets_range_capture_profile(
  metadata : @catalog.RangeConstructionMetadata,
  capture_bytes : Int,
  capture_nodes : Int,
  capture_depth : Int,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  clear : Bool,
) -> Array[@execution.ExecutionCapacity]? {
  if capture_bytes < 1 || capture_nodes < 1 || capture_depth < 1 {
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
  let b = Int::min(wire.to_int(), metadata.limits.max_bytes)
  let n = Int::min(nodes.to_int(), metadata.limits.max_nodes)
  guard sheets_decoded_construction(b, n, metadata.limits.max_depth)
    is Some(input) &&
    sheets_range_json_inventory(wire.to_int(), nodes.to_int()) is Some(native) &&
    @canonical.nfc_lf_construction_extent(wire.to_int()) is Some(normalization) &&
    sheets_writer_units(wire.to_int(), nodes.to_int(), capture_depth)
    is Some(writer) &&
    @source.json_literal_construction_extent(
      wire.to_int(),
      nodes.to_int(),
      capture_depth,
    )
    is Some(host) &&
    sheets_constructor_capacity([
      input,
      input,
      native,
      native,
      {
        record_headers: normalization.record_headers,
        reference_slots: normalization.reference_slots,
        scalar_words: normalization.scalar_words,
        owned_utf16_units: normalization.owned_utf16_units + wire,
        owned_wire_bytes: 2L * wire,
      },
      writer,
      writer,
      {
        record_headers: host.record_headers,
        reference_slots: host.reference_slots,
        scalar_words: host.scalar_words,
        owned_utf16_units: host.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(fixed) &&
    sheets_range_request_capacity(
      metadata, input_bytes, input_nodes, input_depth, clear,
    )
    is Some(row) else {
    return None
  }
  Some([fixed, row])
}

///|
#export_name("sheetsRangeConstructionProfile")
pub fn sheets_range_construction_profile(
  binding : @catalog.RangeBinding,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  response_bytes : Int,
  response_nodes : Int,
  response_depth : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  let metadata = @catalog.range_construction_metadata(binding)
  guard sheets_range_request_capacity(
      metadata, input_bytes, input_nodes, input_depth, false,
    )
    is Some(request) &&
    sheets_range_response_capacity(
      response_bytes, response_nodes, response_depth,
    )
    is Some(response) else {
    return None
  }
  Some([
    (
      request,
      None,
      Some({
        max_input_bytes: metadata.limits.max_bytes,
        max_nodes: metadata.limits.max_nodes,
        max_depth: metadata.limits.max_depth,
      }),
    ),
    (response, None, Some({ max_input_bytes: 64, max_nodes: 3, max_depth: 1, })),
  ])
}

///|
#export_name("sheetsClearConstructionProfile")
pub fn sheets_clear_construction_profile(
  binding : @catalog.ClearRangeBinding,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  response_bytes : Int,
  response_nodes : Int,
  response_depth : Int,
) -> Array[
  (@execution.ExecutionCapacity, @source.ParseLimits?, @source.ParseLimits?),
]? {
  let metadata = @catalog.clear_range_construction_metadata(binding)
  guard sheets_range_request_capacity(
      metadata, input_bytes, input_nodes, input_depth, true,
    )
    is Some(request) &&
    sheets_range_response_capacity(
      response_bytes, response_nodes, response_depth,
    )
    is Some(response) else {
    return None
  }
  Some([
    (
      request,
      None,
      Some({
        max_input_bytes: metadata.limits.max_bytes,
        max_nodes: metadata.limits.max_nodes,
        max_depth: metadata.limits.max_depth,
      }),
    ),
    (response, None, Some({ max_input_bytes: 64, max_nodes: 3, max_depth: 1, })),
  ])
}

///|
#export_name("sheetsRangeCaptureConstructionProfile")
pub fn sheets_range_capture_construction_profile(
  binding : @catalog.RangeBinding,
  capture_bytes : Int,
  capture_nodes : Int,
  capture_depth : Int,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
) -> Array[@execution.ExecutionCapacity]? {
  sheets_range_capture_profile(
    @catalog.range_construction_metadata(binding),
    capture_bytes,
    capture_nodes,
    capture_depth,
    input_bytes,
    input_nodes,
    input_depth,
    false,
  )
}

///|
#export_name("sheetsClearCaptureConstructionProfile")
pub fn sheets_clear_capture_construction_profile(
  binding : @catalog.ClearRangeBinding,
  capture_bytes : Int,
  capture_nodes : Int,
  capture_depth : Int,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
) -> Array[@execution.ExecutionCapacity]? {
  sheets_range_capture_profile(
    @catalog.clear_range_construction_metadata(binding),
    capture_bytes,
    capture_nodes,
    capture_depth,
    input_bytes,
    input_nodes,
    input_depth,
    true,
  )
}
