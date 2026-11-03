///|
// Actual Local JS JSON.parse/stringify clones over bounded DATA. The ordinary
// supported runtime owns its implementation scratch; this is not a Moon
// Source Parser/JsonDocument constructor. Retain the full returned tree/text
// plus wire/digest peak, including rejected request prefixes. The separate
// native proposal parser remains in installed_standard_host_capture_row_capacity.
fn local_file_store_json_capacity(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @execution.ExecutionCapacity? {
  guard bytes > 0 &&
    nodes > 0 &&
    depth > 0 &&
    @source.json_tree_retained_construction_extent(
      nodes,
      nodes - 1,
      nodes,
      0,
      bytes.to_int64(),
      keep_spans=false,
    )
    is Some(returned) &&
    @execution.preparation_representation_cost({
      record_headers: returned.record_headers,
      reference_slots: returned.reference_slots,
      scalar_words: returned.scalar_words,
      owned_utf16_units: returned.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.execution_capacity(retained, retained) is Some(tree) &&
    @execution.execution_capacity_inventory(
      [{ unit: DecodedTextBytes, count: bytes.to_int64(), copies: 1, }],
      // Canonical text and its digest/encoding input coexist with the returned
      // immutable tree. Sequential calls reuse workspace, never returned DATA.
      [{ unit: CanonicalWireBytes, count: bytes.to_int64(), copies: 1, }],
      RetainedAlongsideExecution,
    )
    is Some(wire) else {
    return None
  }
  @execution.add_execution_capacity(tree, wire)
}

///|
// Local STORE's existing Content child, request/recovery JSON and descriptor
// writer, not the HTTP/Credential recipe. Every quantity is inert DATA for the
// SAME managed Effect Plan. No grant, physical attempt or cleanup ACK is made.
// The passed read window covers only the consuming streaming peak. The SAME
// Content/Store owner must still fund its metadata/read preparation; this quote
// neither replaces that owner nor claims its maxObjectBytes as file backing.
pub fn installed_local_file_store_recipe_capacities(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  preview_bytes : Int,
  preview_nodes : Int,
  preview_depth : Int,
  request_bytes : Int,
  recovery_bytes : Int,
  response_bytes : Int,
  stored_bytes : Int,
  stored_nodes : Int,
  stored_depth : Int,
  native_original_bytes : Int64,
  path_bytes : Int,
  name_bytes : Int,
  max_components : Int,
  native_depth : Int,
  content_read_window_bytes : Int,
  control_wire_bytes? : Int? = None,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  let control_bytes = control_wire_bytes.unwrap_or(stored_bytes)
  if control_bytes < 1 ||
    control_bytes > stored_bytes ||
    native_original_bytes <= 0L ||
    path_bytes < 1 ||
    name_bytes < 1 ||
    name_bytes > path_bytes ||
    max_components < 1 ||
    max_components >= 2147483647 ||
    max_components > native_depth ||
    content_read_window_bytes < 1 ||
    request_bytes < 1 ||
    recovery_bytes < 1 ||
    response_bytes < 1 ||
    stored_bytes < response_bytes {
    return Err(Unsupported)
  }
  // The existing Common export/parser path owns proposal/selector DATA once
  // per checked row. Core applies the actual checked row multiplicity later.
  guard installed_standard_host_capture_row_capacity(
      body_bytes, body_nodes, body_depth,
    )
    is Some(capture_row) &&
    local_file_store_json_capacity(preview_bytes, preview_nodes, preview_depth)
    is Some(preview) &&
    local_file_store_json_capacity(recovery_bytes, preview_nodes, preview_depth)
    is Some(recovery) &&
    standard_create_sequence_pair_capacity(preview, recovery)
    is Some(capture_fixed) &&
    local_file_store_json_capacity(body_bytes, body_nodes, body_depth)
    is Some(input) &&
    local_file_store_json_capacity(request_bytes, body_nodes, body_depth)
    is Some(immutable_request) &&
    // requestFrom serializes BEFORE enforcing its accepted request ceiling.
    // Keep the original body and selector/Preview envelope on failure, not
    // only the smaller accepted immutable request. No caller bound is raised.
    standard_create_sum_capacities(
      [input, preview, immutable_request],
      sequential_workspace=true,
    )
    is Some(request) &&
    @execution.execution_capacity_inventory_add(
      0L,
      QuotedBytes,
      native_original_bytes,
      max_components + 1,
    )
    is Some(descriptors) &&
    @execution.execution_capacity_inventory(
      [
        // Root, at most components-1 ancestors, and writer each own a real
        // native descriptor allocation. Its sizeof already includes names.
        { unit: QuotedBytes, count: descriptors, copies: 1, },
        { unit: QuotedBytes, count: response_bytes.to_int64(), copies: 1, },
        { unit: DecodedTextBytes, count: path_bytes.to_int64(), copies: 1, },
      ],
      [
        {
          unit: QuotedBytes,
          count: content_read_window_bytes.to_int64(),
          copies: 1,
        },
        {
          unit: CanonicalWireBytes,
          count: response_bytes.to_int64(),
          copies: 1,
        },
      ],
      RetainedAlongsideExecution,
    )
    is Some(physical) &&
    standard_create_saved_control_capacity(
      control_bytes, stored_nodes, stored_depth,
    )
    is Some(saved) &&
    local_file_store_json_capacity(response_bytes, stored_nodes, stored_depth)
    is Some(projected) &&
    @execution.execution_capacity_inventory(
      // Same SQLite response and its existing Buffer.from materialization.
      [{ unit: QuotedBytes, count: stored_bytes.to_int64(), copies: 2, }],
      [],
      RetainedAlongsideExecution,
    )
    is Some(stored_buffers) &&
    standard_create_sum_capacities(
      [saved, stored_buffers, projected],
      sequential_workspace=true,
    )
    is Some(controls) else {
    return Err(Unsupported)
  }
  // Local's saved request envelope has no separately copied effect-id field.
  // Common's existing proposal/Preview body already owns that text. This is
  // the absent additive term, not an unfunded construction/physical extent.
  let no_additional_effect_id = @execution.execution_capacity(0L, 0L).unwrap()
  Ok([
    capture_fixed, capture_row, request, physical, controls, no_additional_effect_id,
  ])
}

///|
/// Closed existing Ledger fields and the Local driver's applied-empty-result
/// receipt. All strings here are ASCII keys/enums or validated SHA256 CIDs.
/// The same installed codec limit must reject larger saved prefixes before
/// parsing. This is not a bound on arbitrary provider outcomes.
pub fn installed_local_file_store_control_wire_bound() -> Int {
  installed_effect_control_wire_bound(
    "{\"result\":{},\"state\":\"applied\"}".length(),
    1000000,
  ).unwrap()
}
