///|
// The selected non-HTTP writer supplies its actual construction original.
// Common retains it unchanged and adds only its existing JSON/capture/control
// constructors. Neither the quote nor transfer bound admits a physical attempt.
pub fn installed_physical_write_recipe_capacities(
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
  physical : @execution.ExecutionCapacity,
  control_wire_bytes? : Int? = None,
  request_construction? : @execution.ExecutionCapacity? = None,
) -> Result[Array[@execution.ExecutionCapacity], ClientInstalledManagedRunIssue] {
  let control_bytes = control_wire_bytes.unwrap_or(stored_bytes)
  if control_bytes < 1 ||
    control_bytes > stored_bytes ||
    stored_bytes < response_bytes ||
    response_bytes < 1 {
    return Err(Unsupported)
  }
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
    standard_create_saved_control_capacity(
      control_bytes, stored_nodes, stored_depth,
    )
    is Some(saved) &&
    local_file_store_json_capacity(response_bytes, stored_nodes, stored_depth)
    is Some(projected) &&
    @execution.execution_capacity_inventory(
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
  let no_additional_effect_id = @execution.execution_capacity(0L, 0L).unwrap()
  let request = match request_construction {
    Some(original) => {
      // The installed file child reads the selected row and detaches its
      // bounded record. The member capture owns Preview decoding and saved
      // material through cleanup; this row child never parses a Preview.
      guard standard_create_sequence_pair_capacity(input, immutable_request)
        is Some(row) &&
        @execution.add_execution_capacity(row, original) is Some(combined) else {
        return Err(Unsupported)
      }
      combined
    }
    None => {
      // Keep the original complete request envelope for existing callers.
      // Only the member capture retains the whole Preview after construction.
      guard standard_create_sum_capacities(
          [input, preview, immutable_request],
          sequential_workspace=true,
        )
        is Some(envelope) &&
        @execution.execution_capacity(
          @execution.execution_capacity_retained_bytes(envelope) -
          @execution.execution_capacity_retained_bytes(preview),
          @execution.execution_capacity_execution_bytes(envelope),
        )
        is Some(capacity) else {
        return Err(Unsupported)
      }
      capacity
    }
  }
  Ok([
    capture_fixed, capture_row, request, physical, controls, no_additional_effect_id,
  ])
}

///|
// A guarded file Effect constructs a span-free immutable request/response.
// Its original Bytes/parser/cursors do not escape that constructor. Preserve
// their complete construction/failure peak as workspace beside the provider's
// actual returned values; completion is still the SAME operation token's duty.
pub fn installed_file_effect_constructor_capacity(
  provider : @execution.ExecutionCapacity,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[@execution.ExecutionCapacity, ClientInstalledManagedRunIssue] {
  guard installed_json_effect_request_construction_capacity(
      provider, bytes, nodes, depth,
    )
    is Some(complete) &&
    @execution.execution_capacity(
      @execution.execution_capacity_retained_bytes(provider),
      @execution.execution_capacity_execution_bytes(complete),
    )
    is Some(capacity) else {
    return Err(Unsupported)
  }
  Ok(capacity)
}

///|
/// The original file and checked changes stay borrowed from the caller. The
/// replacement stays on this constructor's operation until its last use.
/// Physical transport and the File attempt have their own extents.
pub fn prepare_installed_file_update_wire_extent(
  layout : @row_source_host.RelationTargetWriteWireConstruction,
) -> Result[
  ClientInstalledEffectOperationExtent,
  ClientInstalledManagedRunIssue,
] {
  let returned : @execution.PreparationRepresentationUnits = {
    record_headers: 2L,
    reference_slots: 3L,
    scalar_words: 1L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  let (retained, peak) = if layout.encoded_change_bytes == 0L {
    // Before a row has supplied changes, the Plan holds only the carrier.
    guard @execution.preparation_representation_cost(returned) is Some(bytes) else {
      return Err(Unsupported)
    }
    (bytes, bytes)
  } else {
    guard @execution.preparation_representation_cost({
        ..returned,
        owned_wire_bytes: layout.replacement_bytes,
      })
      is Some(retained) &&
      @execution.compose_preparation_representation([returned, layout.placement])
      is Some(units) &&
      @execution.preparation_representation_cost(units) is Some(peak) else {
      return Err(Unsupported)
    }
    (retained, peak)
  }
  guard @execution.execution_capacity(retained, peak) is Some(capacity) else {
    return Err(Unsupported)
  }
  prepare_installed_effect_operation_extent(
    "python.mock.file.replacement-wire", capacity, 0L, false,
  )
}
