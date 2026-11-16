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
// The Local footprint borrows each original request and owns one target CID.
// Keep the target Array's growing slots and the temporary duplicate Set on
// the SAME control token until retirement. The Map entry recipe bounds a Set
// entry's single borrowed key, links and growing buckets. Its fixed headers
// and one bounded basename/hash constructor use the declared .footprint
// member scratch; global boundary/scheme Strings remain borrowed constants.
fn local_file_store_footprint_target_capacity() -> @execution.ExecutionCapacity? {
  guard @shape.collection_construction_extent({
      // One returned CID String header/length word per original row.
      records: 1L,
      record_references: 0L,
      record_words: 1L,
      reference_arrays: 0L,
      reference_items: 1L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 1L,
    })
    is Some(target) &&
    @execution.preparation_representation_cost({
      record_headers: target.record_headers,
      reference_slots: target.reference_slots,
      scalar_words: target.scalar_words,
      owned_utf16_units: 71L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) else {
    return None
  }
  // This deliberately retains the growing Set/Array peak, including an
  // opaque fallback's prefix. A successful constructor returns only scratch;
  // it does not pretend to release this original control DATA early.
  @execution.execution_capacity(retained, retained)
}

///|
// The original issuer borrows the checked decision and three CID Strings.
// Its empty proof, WeakMap value and returned carrier survive construction.
// The same row later holds {proof,useId}; the closed common use-id template
// borrows two 71-unit CIDs, "-write-", a hyphen and ten Int-index digits.
// WeakMap entries are not a cleanup ACK: keep their full per-occurrence cost
// until the original row/control aliases have drained at Run retirement.
fn local_file_store_grant_capacity() -> @execution.ExecutionCapacity? {
  guard @shape.collection_construction_extent({
      records: 5L,
      record_references: 7L,
      record_words: 2L,
      reference_arrays: 0L,
      reference_items: 0L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 1L,
    })
    is Some(held) else {
    return None
  }
  standard_create_representation_capacity(
    {
      record_headers: held.record_headers,
      reference_slots: held.reference_slots,
      scalar_words: held.scalar_words,
      owned_utf16_units: 2L * 71L + 8L + 10L,
      owned_wire_bytes: 0L,
    },
    {
      // Destructured issuer frame (seven borrowed refs), Map.set receiver
      // and two arguments, and the nonoverlapping Object.freeze argument.
      // Original Account/current frames remain in the common control floor.
      record_headers: 3L,
      reference_slots: 11L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  )
}

///|
// The warm File capture initially retains only its proposal-reference Array;
// generated proposal Strings remain borrowed from the original completed Read.
// Reserve its wrapper/backing, four spare references and geometric-growth
// overlap. No JSON tree, request, physical writer or recovery body exists yet.
pub fn installed_local_file_store_initial_constructor_capacities() -> Array[
  @execution.ExecutionCapacity,
] {
  let fixed = @execution.preparation_representation_cost({
    // Proposal Array plus its two installing-code member task callbacks.
    // These retain at most 36 existing context references and four
    // phase/index words while its original asynchronous task is joined.
    record_headers: 5L,
    reference_slots: 41L,
    scalar_words: 6L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let row = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 2L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let row_growth = @execution.preparation_representation_cost({
    record_headers: 0L,
    reference_slots: 3L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // The row constructor's native payload is selected before prepare; until
  // then its original closure retains a context reference, not a parsed body.
  let request = @execution.preparation_representation_cost({
    record_headers: 1L,
    reference_slots: 1L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  [
    @execution.execution_capacity(fixed, fixed).unwrap(),
    @execution.execution_capacity(row, row_growth).unwrap(),
    @execution.execution_capacity(request, request).unwrap(),
  ]
}

///|
// Select the SAME warm constructor from already-owned generated proposal
// wire geometry. The full Preview is constructed/admitted by its existing
// shared control Owner; a member borrows it and does not parse another copy.
// All actual member/row copies remain distinct retained quantities. These
// capacities do not select input policy, a Resource budget or send authority.
// The original structural/callback backing remains alongside the output.
pub fn installed_local_file_store_observed_constructor_capacities(
  body_bytes : Int,
  body_nodes : Int,
  body_depth : Int,
  request_bytes : Int,
  request_nodes : Int,
  recovery_bytes : Int,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  if recovery_bytes < 1 {
    return Err(Unsupported)
  }
  let empty = body_bytes == 0 &&
    body_nodes == 0 &&
    request_bytes == 0 &&
    request_nodes == 0
  let row = if empty {
    Some(installed_local_file_store_initial_constructor_capacities()[1])
  } else {
    installed_standard_host_capture_row_capacity(
      body_bytes, body_nodes, body_depth,
    )
  }
  let request = if empty {
    // No row/request is constructed. Keep its unchanged initial structural
    // extent; only the actual empty recovery envelope needs a member quote.
    Some(installed_local_file_store_initial_constructor_capacities()[2])
  } else {
    match
      (
        local_file_store_json_capacity(body_bytes, body_nodes, body_depth),
        local_file_store_json_capacity(request_bytes, request_nodes, body_depth),
      ) {
      (Some(input), Some(request)) =>
        standard_create_sum_capacities(
          [input, request],
          sequential_workspace=true,
        )
      _ => None
    }
  }
  guard row is Some(row) &&
    request is Some(request) &&
    // Warm recoveryEntry serializes already-owned immutable request records;
    // it does not parse another Preview/recovery tree. Its actual output is
    // one record, the retained wire and its digest. Row-string/join/hash work
    // remains beside that output until this same constructor completes.
    @execution.preparation_representation_cost({
      record_headers: 3L,
      reference_slots: 3L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(recovery_control) &&
    @execution.execution_capacity_inventory(
      [
        { unit: QuotedBytes, count: recovery_control, copies: 1, },
        { unit: DecodedTextBytes, count: recovery_bytes.to_int64(), copies: 1, },
        { unit: DecodedTextBytes, count: 71L, copies: 1, },
      ],
      [
        { unit: DecodedTextBytes, count: recovery_bytes.to_int64(), copies: 1, },
        {
          unit: CanonicalWireBytes,
          count: recovery_bytes.to_int64(),
          copies: 1,
        },
      ],
      RetainedAlongsideExecution,
    )
    is Some(recovery) &&
    @execution.add_execution_capacity(
      installed_local_file_store_initial_constructor_capacities()[0],
      recovery,
    )
    is Some(recovery) else {
    return Err(Unsupported)
  }
  Ok([recovery, row, request])
}

///|
// Cold Local recovery parses exactly its own saved member envelope. The
// already-admitted whole Preview remains borrowed from the original control
// owner. Keep this tree and each immutable request clone as separate live
// quantities; request cloning never releases the saved tree's backing.
// The initial original member callbacks remain live alongside both. The sum
// of all cloned record trees is bounded by the SAME complete saved envelope;
// it is not another complete envelope for each row. Per-row handles remain
// separately additive after the actual checked row multiplicity is known.
pub fn installed_local_file_store_observed_recovery_capacities(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  guard local_file_store_json_capacity(bytes, nodes, depth) is Some(saved) &&
    local_file_store_json_capacity(bytes, nodes, depth) is Some(clone) &&
    standard_create_sum_capacities([saved, clone], sequential_workspace=true)
    is Some(forests) &&
    @execution.add_execution_capacity(
      installed_local_file_store_initial_constructor_capacities()[0],
      forests,
    )
    is Some(fixed) &&
    @execution.preparation_representation_cost({
      // Empty request handle, original WeakMap record, transient requestFacts
      // and returned row entry. Include three spare reference slots.
      record_headers: 4L,
      reference_slots: 16L,
      scalar_words: 1L,
      owned_utf16_units: 71L,
      owned_wire_bytes: 0L,
    })
    is Some(control) &&
    @execution.execution_capacity(control, control) is Some(row) else {
    return Err(Unsupported)
  }
  Ok([fixed, row])
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
  control_response_bytes? : Int? = None,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  let control_bytes = control_wire_bytes.unwrap_or(stored_bytes)
  let response_read_bytes = control_response_bytes.unwrap_or(stored_bytes)
  if control_bytes < 1 ||
    control_bytes > stored_bytes ||
    response_read_bytes < 1 ||
    response_read_bytes > stored_bytes ||
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
      // The receiver bounds the native SQLite BLOB BEFORE materialization.
      // Its Buffer.from copy overlaps that row; if both single/batch records
      // exist, the prior single Buffer survives the second copy until refusal.
      [{ unit: QuotedBytes, count: response_read_bytes.to_int64(), copies: 3, }],
      [],
      RetainedAlongsideExecution,
    )
    is Some(stored_buffers) &&
    standard_create_sum_capacities(
      [saved, stored_buffers, projected],
      sequential_workspace=true,
    )
    is Some(controls) &&
    local_file_store_footprint_target_capacity() is Some(footprint_target) &&
    @execution.add_execution_capacity(controls, footprint_target)
    is Some(controls) &&
    local_file_store_grant_capacity() is Some(grant) &&
    @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(grant),
      @execution.execution_capacity_retained_bytes(grant),
    )
    is Some(grant_held) &&
    @execution.add_execution_capacity(controls, grant_held) is Some(controls) &&
    @execution.execution_capacity(
      0L,
      @execution.execution_capacity_execution_bytes(grant) -
      @execution.execution_capacity_retained_bytes(grant),
    )
    is Some(grant_workspace) else {
    return Err(Unsupported)
  }
  // Local's saved request envelope has no separately copied effect-id field.
  // Common's existing proposal/Preview body already owns that text. This is
  // the absent additive term, not an unfunded construction/physical extent.
  let no_additional_effect_id = @execution.execution_capacity(0L, 0L).unwrap()
  Ok([
    capture_fixed, capture_row, request, physical, controls, no_additional_effect_id,
    // R is already multiplied by the SAME checked row count in controls.
    // Native construction selects only this synchronous W; it adds no R a
    // second time and completion never returns the retained proof population.
     grant_workspace,
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
