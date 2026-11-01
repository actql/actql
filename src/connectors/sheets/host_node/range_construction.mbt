///|
// range_parse retains no decoder Cursor. Its original Source parser supplies
// the bounded grammar/key/text proof before the native Json constructor.
fn sheets_range_parsed_construction(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @decode.preserving_json_parser_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(original) else {
    return None
  }
  Some({
    record_headers: original.record_headers,
    reference_slots: original.reference_slots,
    scalar_words: original.scalar_words,
    owned_utf16_units: original.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

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
    sheets_range_parsed_construction(configuration_bytes, 10 + 4 * columns, 32)
    is Some(configuration) &&
    sheets_range_parsed_construction(
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
      // The same admitted binding now retains its original native target.
      record_references: columns.to_int64() + 11L,
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
fn sheets_range_request_profile(
  metadata : @catalog.RangeConstructionMetadata,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  clear : Bool,
) -> (@execution.ExecutionCapacity, @source.ParseLimits)? {
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
  // A successful update has exactly the declared rectangle and scalar cells.
  // Its write document has at least as many value nodes as the returned input
  // rows. Clear returns an empty value. The original target is immutable JSON;
  // its node/text population is bounded by its original UTF16 spelling.
  let returned_nodes = Int64::min(n.to_int64(), output.body_nodes.to_int64()) +
    metadata.target_units.to_int64() +
    16L
  let request_controls : @execution.PreparationRepresentationUnits = {
    record_headers: 3L,
    reference_slots: if clear {
      14L
    } else {
      15L
    },
    scalar_words: 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard sheets_range_parsed_construction(b, n, d) is Some(input) &&
    sheets_range_parsed_construction(
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
    sheets_range_json_inventory(facts_bytes.to_int(), returned_nodes.to_int())
    is Some(native_output) &&
    sheets_range_json_inventory(target_bytes.to_int(), n) is Some(native_target) &&
    sheets_range_canonical_construction(n, metadata.limits.max_depth)
    is Some(target_canonical) &&
    sheets_writer_units(target_bytes.to_int(), n, metadata.limits.max_depth)
    is Some(target_writer) &&
    sheets_range_canonical_construction(n, d) is Some(value_canonical) &&
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
  // Clear's successful input is exactly {}; its returned fields contain only
  // the original binding and one validated UUID. The full arbitrary input
  // bound above still backs every pre-refusal parser and failed constructor.
  let output_bytes = if clear {
    6L *
    (
      metadata.target_units.to_int64() +
      metadata.origin_units.to_int64() +
      metadata.spreadsheet_units.to_int64() +
      @catalog.clear_marker_text_units().to_int64()
    ) +
    1024L
  } else {
    facts_bytes
  }
  let output_limits : @source.ParseLimits = {
    max_input_bytes: Int64::min(
      output_bytes,
      metadata.limits.max_bytes.to_int64(),
    ).to_int(),
    max_nodes: Int64::min(returned_nodes, metadata.limits.max_nodes.to_int64()).to_int(),
    max_depth: metadata.limits.max_depth,
  }
  let zero : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard (if clear {
      Some(zero)
    } else {
      // Only a successful rectangle escapes into the original request. The
      // original outgoing body contains at least all those scalar value nodes.
      // Invalid wider/deeper input still uses the full parser phases below.
      sheets_range_json_inventory(b, Int::min(n, output.body_nodes))
    })
    is Some(retained_value) &&
    @execution.compose_preparation_representation([
      retained_value,
      {
        ..request_controls,
        owned_utf16_units: Int64::min(
          output.body_bytes.to_int64(),
          metadata.limits.max_bytes.to_int64(),
        ) +
        (if clear {
          @catalog.clear_marker_text_units().to_int64()
        } else {
          Int64::min(facts_bytes, metadata.limits.max_bytes.to_int64())
        }) +
        metadata.spreadsheet_units.to_int64() +
        128L +
        output_limits.max_input_bytes.to_int64(),
        owned_wire_bytes: 0L,
      },
    ])
    is Some(returned) else {
    return None
  }
  let original_text = {
    ..zero,
    // Original UTF8 encodings remain coheld with the parser/native result.
    // These rejection envelopes are unchanged by retaining successful JSON.
    owned_utf16_units: 2L * input_bytes.to_int64() +
    target_bytes +
    facts_bytes +
    output.body_bytes.to_int64(),
    owned_wire_bytes: 2L * input_bytes.to_int64() +
    target_bytes +
    3L * output.body_bytes.to_int64() +
    metadata.origin_units.to_int64() * 3L +
    128L,
  }
  guard @execution.compose_preparation_representation([original_text, target])
    is Some(target_source) &&
    @execution.compose_preparation_representation([
      original_text, native_target, target_canonical, target_writer,
    ])
    is Some(target_value) &&
    @execution.compose_preparation_representation([original_text, input])
    is Some(value_source) &&
    @execution.compose_preparation_representation([
      original_text, native_input, native_input, validation, value_canonical, body_writer,
      facts_writer,
    ])
    is Some(value_request) &&
    @execution.compose_preparation_representation([
      // Facts use the SAME original value/target. Their trees are retained
      // above or by the binding; no second Source parser or input Json tree.
      original_text, native_output, facts_writer,
    ])
    is Some(facts) &&
    sheets_range_capture_phase_capacity(returned, [
      target_source, target_value, value_source, value_request, facts,
    ])
    is Some(native) else {
    return None
  }
  Some((native, output_limits))
}

///|
fn sheets_range_request_capacity(
  metadata : @catalog.RangeConstructionMetadata,
  input_bytes : Int,
  input_nodes : Int,
  input_depth : Int,
  clear : Bool,
) -> @execution.ExecutionCapacity? {
  guard sheets_range_request_profile(
      metadata, input_bytes, input_nodes, input_depth, clear,
    )
    is Some((native, output)) &&
    @source.json_literal_construction_extent(
      output.max_input_bytes,
      output.max_nodes,
      output.max_depth,
    )
    is Some(literal) &&
    sheets_constructor_capacity([
      {
        record_headers: literal.record_headers,
        reference_slots: literal.reference_slots,
        scalar_words: literal.scalar_words,
        owned_utf16_units: literal.owned_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(host) else {
    return None
  }
  // Fresh rows get this Host constructor from the existing Core composer.
  // Direct recovery instead needs the complete native+Host quantity here.
  // Neither route constructs or prices the Host projection twice.
  @execution.add_execution_capacity(native, host)
}

///|
// classify_append opens one root Map. classify_clear opens at most five
// root/second/create/metadata/location Maps. Their fields are disjoint Source
// nodes; entries across all maps cannot exceed the SAME total node bound.
// elements(replies) does materialize every supplied reply Cursor before its
// later cardinality refusal, so retain that entire Array and every Cursor.
fn sheets_range_ack_projection_construction(
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  let cursor = @decode.cursor_construction_extent()
  let child = @decode.indexed_child_construction_extent()
  let n = nodes.to_int64()
  guard @shape.collection_construction_extent({
      records: n * cursor.record_headers,
      record_references: n * cursor.reference_slots,
      record_words: n * cursor.scalar_words,
      reference_arrays: 1L,
      reference_items: n,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 5L,
      map_entries: n,
    })
    is Some(collections) &&
    @decode.issue_construction_extent(depth + 1) is Some(issue) else {
    return None
  }
  @execution.compose_preparation_representation([
    sheets_collection_units(collections),
    sheets_collection_units(issue),
    // The ten original lookups plus their scalar/Option/result carriers fit
    // within the original sixteen-child envelope, co-held with all maps.
    {
      record_headers: 16L * child.record_headers,
      reference_slots: 16L * child.reference_slots,
      scalar_words: 16L * child.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
// clear_marker_value has exactly eight Json nodes, seven fields and two
// objects. Its canonical projection borrows all original text (data_keys),
// retains seventeen value/FrozenArray/pair records and the two field vectors.
// Back its live depth-two BuildFrames, seen-key Maps and current sort scratch
// through the SAME collection/iterator owners, not another parser/index.
fn sheets_clear_ack_marker_construction() -> @execution.PreparationRepresentationUnits? {
  guard @shape.collection_construction_extent({
      records: 17L + 5L + 1L + 6L,
      record_references: 24L + 15L + 8L,
      record_words: 16L + 10L + 3L + 6L,
      // Two output field arrays, one pending-frame array, one sort scratch.
      reference_arrays: 4L,
      reference_items: 7L + 5L + 7L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 2L,
      map_entries: 7L,
    })
    is Some(body) else {
    return None
  }
  let iter = @shape.reference_map_iterator_construction_extent()
  let next = @shape.reference_map_iterator_next_construction_extent()
  @execution.compose_preparation_representation([
    sheets_collection_units(body),
    {
      record_headers: 2L * iter.record_headers + next.record_headers,
      reference_slots: 2L * iter.reference_slots + next.reference_slots,
      scalar_words: 2L * iter.scalar_words + next.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
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
    sheets_range_ack_projection_construction(nodes, depth) is Some(projection) &&
    sheets_writer_units(64, 3, 1) is Some(writer) &&
    // Clear additionally canonicalizes the fixed marker+five-coordinate
    // object. A36-ASCII marker, Int coordinates and original field syntax
    // fit256 bytes/eight nodes/depth2. Range safely shares this closed bound.
    sheets_range_json_inventory(256, 8) is Some(marker) &&
    sheets_clear_ack_marker_construction() is Some(marker_projection) &&
    sheets_writer_units(256, 8, 2) is Some(marker_writer) &&
    @execution.compose_preparation_representation([
      input, projection, marker, marker_projection, marker_writer, writer,
    ])
    is Some(workspace) else {
    return None
  }
  // Only the Native outcome String escapes this synchronous projection.
  // The input Source/index/maps/reply Cursors and failure path do not escape.
  // Common separately backs its declared64-byte Host output JSON projection.
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 1L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 64L,
      owned_wire_bytes: 0L,
    },
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// CanonicalValue/FrozenArray/field pairs, the active BuildFrame stack, seen
// keys and sort scratch in canonical_json.from_json(data_keys=true). Text is
// borrowed from the preceding native/normalization owner. This is the actual
// range_canonical constructor, not another parse or normalization quote.
fn sheets_range_canonical_construction(
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  let n = nodes.to_int64()
  let d = Int::min(nodes, depth).to_int64()
  let frames = 2L * d + 4L
  guard @shape.collection_construction_extent({
      records: 3L * n + frames + 1L + 6L,
      record_references: 4L * n + 3L * frames + 8L,
      record_words: 2L * n + 2L * frames + 3L + 6L,
      // Owned output vectors, one pending stack and current sort scratch.
      reference_arrays: n + 2L,
      reference_items: 2L * n + frames,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: d,
      map_entries: n,
    })
    is Some(body) else {
    return None
  }
  let iter = @shape.reference_map_iterator_construction_extent()
  let next = @shape.reference_map_iterator_next_construction_extent()
  @execution.compose_preparation_representation([
    sheets_collection_units(body),
    {
      record_headers: d * iter.record_headers + next.record_headers,
      reference_slots: d * iter.reference_slots + next.reference_slots,
      scalar_words: d * iter.scalar_words + next.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}

///|
fn sheets_range_normalization_construction(
  bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  guard @canonical.nfc_lf_construction_extent(bytes) is Some(value) else {
    return None
  }
  Some({
    record_headers: value.record_headers,
    reference_slots: value.reference_slots,
    scalar_words: value.scalar_words,
    owned_utf16_units: value.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// Declared synchronous alternatives of this SAME capture/recovery callback.
// Their peak uses the common representation and tariff exactly once. Returned
// material remains separate; no Resource, current observation or release ACK.
fn sheets_range_capture_phase_capacity(
  retained : @execution.PreparationRepresentationUnits,
  phases : Array[@execution.PreparationRepresentationUnits],
) -> @execution.ExecutionCapacity? {
  let mut peak : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  for phase in phases {
    peak = {
      record_headers: Int64::max(peak.record_headers, phase.record_headers),
      reference_slots: Int64::max(peak.reference_slots, phase.reference_slots),
      scalar_words: Int64::max(peak.scalar_words, phase.scalar_words),
      owned_utf16_units: Int64::max(
        peak.owned_utf16_units,
        phase.owned_utf16_units,
      ),
      owned_wire_bytes: Int64::max(
        peak.owned_wire_bytes,
        phase.owned_wire_bytes,
      ),
    }
  }
  @execution.preparation_execution_capacity({
    retained,
    workspace: peak,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// The actual pre-NFC guards for fresh and saved metadata, respectively.
// Clear canonicalizes its reconstructed expected metadata before NFC; range
// additionally has its earlier independent saved-wire byte guard.
fn sheets_range_capture_normalization_inputs(
  binding_bytes : Int,
  recovery_bytes : Int,
  clear : Bool,
) -> (Int, Int) {
  (
    binding_bytes,
    if clear {
      recovery_bytes
    } else {
      Int::min(recovery_bytes, @catalog.range_saved_recovery_wire_byte_limit())
    },
  )
}

///|
// Fixed metadata text already admitted by this SAME binding. Clear validates
// its row markers and canonical(expected)==wire BEFORE normalizing expected;
// unrelated fields in a supplied recovery tree never reach that NFC call.
// Marker text and metadata-node growth are charged per checked request row.
// effect_id alone is supplied later by the SAME checked member template.
fn sheets_range_recovery_metadata_text_units(
  metadata : @catalog.RangeConstructionMetadata,
) -> Int64? {
  guard @execution.checked_preparation_add_product(
      1024L,
      metadata.schema_bytes,
      1L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      metadata.identity_units,
      1L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      metadata.target_units.to_int64(),
      3L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      metadata.origin_units.to_int64(),
      1L,
    )
    is Some(total) &&
    @execution.checked_preparation_add_product(
      total,
      metadata.spreadsheet_units.to_int64(),
      1L,
    )
    is Some(total) else {
    return None
  }
  Some(total)
}

///|
// Affine growth from the SAME Unicode Owner, not another byte tariff or cap.
// Header/ref/fixed controls cancel; the maximum per-unit coordinate bounds
// both normalization scratch and the separately retained normalized text.
fn sheets_range_effect_id_capacity() -> @execution.ExecutionCapacity? {
  guard @canonical.nfc_lf_construction_extent(0) is Some(zero) &&
    @canonical.nfc_lf_construction_extent(1) is Some(one) else {
    return None
  }
  let none : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  @execution.preparation_execution_capacity({
    retained: none,
    workspace: {
      record_headers: one.record_headers - zero.record_headers,
      reference_slots: one.reference_slots - zero.reference_slots,
      scalar_words: one.scalar_words - zero.scalar_words,
      owned_utf16_units: Int64::max(
        one.owned_utf16_units - zero.owned_utf16_units,
        one.max_output_utf16_units - zero.max_output_utf16_units,
      ),
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// One original validated UUID marker belongs to one checked request row.
// Compose its additive metadata families through their existing Owners. The
// enclosing member retains its full wire/forest bounds; this is only the
// proportional fresh/saved metadata workspace, with no new policy or grant.
fn sheets_clear_recovery_marker_capacity(
  depth : Int,
) -> @execution.ExecutionCapacity? {
  let units = @catalog.clear_marker_text_units()
  // The marker is ASCII, but preserve the general JSON escaping envelope.
  let bytes = 6 * units + 3
  guard sheets_range_parsed_construction(bytes, 1, depth) is Some(parsed) &&
    sheets_range_json_inventory(bytes, 1) is Some(native) &&
    sheets_range_canonical_construction(1, depth) is Some(canonical) &&
    sheets_writer_units(bytes, 1, depth) is Some(writer) &&
    sheets_range_normalization_construction(units) is Some(normalization) &&
    @canonical.nfc_lf_construction_extent(units) is Some(text) &&
    @shape.collection_construction_extent({
      // Marker selection, seen-map admission and original ordered vectors.
      records: 2L,
      record_references: 4L,
      record_words: 2L,
      reference_arrays: 3L,
      reference_items: 3L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: 1L,
    })
    is Some(slots) &&
    @execution.compose_preparation_representation([
      parsed,
      native,
      native,
      canonical,
      writer,
      writer,
      normalization,
      sheets_collection_units(slots),
      {
        record_headers: 1L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: text.max_output_utf16_units,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(workspace) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace,
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
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
    sheets_range_json_inventory(b, n) is Some(native) &&
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
    is Some(entry) &&
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
  guard @execution.compose_preparation_representation([
      inputs, input, native, native,
    ])
    is Some(parse_peak) &&
    @execution.compose_preparation_representation([
      inputs, native, native, entry_input, entry,
    ])
    is Some(entry_peak) &&
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
      parse_peak, entry_peak, normalize_peak, canonical_peak, expected_peak, metadata_parse_peak,
      metadata_normalize_peak, metadata_canonical_peak,
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
  guard sheets_range_request_profile(
      metadata, input_bytes, input_nodes, input_depth, false,
    )
    is Some((request, output)) &&
    sheets_range_response_capacity(
      response_bytes, response_nodes, response_depth,
    )
    is Some(response) else {
    return None
  }
  Some([
    (request, None, Some(output)),
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
  guard sheets_range_request_profile(
      metadata, input_bytes, input_nodes, input_depth, true,
    )
    is Some((request, output)) &&
    sheets_range_response_capacity(
      response_bytes, response_nodes, response_depth,
    )
    is Some(response) else {
    return None
  }
  Some([
    (request, None, Some(output)),
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
  recovery_bytes : Int,
  recovery_nodes : Int,
  recovery_depth : Int,
) -> Array[@execution.ExecutionCapacity]? {
  sheets_range_capture_profile(
    @catalog.range_construction_metadata(binding),
    capture_bytes,
    capture_nodes,
    capture_depth,
    input_bytes,
    input_nodes,
    input_depth,
    recovery_bytes,
    recovery_nodes,
    recovery_depth,
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
  recovery_bytes : Int,
  recovery_nodes : Int,
  recovery_depth : Int,
) -> Array[@execution.ExecutionCapacity]? {
  sheets_range_capture_profile(
    @catalog.clear_range_construction_metadata(binding),
    capture_bytes,
    capture_nodes,
    capture_depth,
    input_bytes,
    input_nodes,
    input_depth,
    recovery_bytes,
    recovery_nodes,
    recovery_depth,
    true,
  )
}
